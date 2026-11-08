defmodule StockFetcher.Trading.SaveFile do
  @moduledoc """
  The save file (2026-11-07): a portfolio as readable, signed JSON, so the server doesn't have
  to keep anyone's progress and there are no accounts.

  Why the server doesn't keep it: one shared portfolio meant anyone could change anyone's
  state, and accounts (sign-up, passwords, recovery) would blow up the scope. Instead each tab
  gets a private session portfolio (`Trading.create_session_portfolio/2`), the browser keeps
  the latest save (autosave in localStorage) and the user can download it and import it later.

  Why signed: the file is plain JSON, so anyone can read it, but an edited file (say, cash
  changed to $1 billion) is refused on import. A paper-trading record is only useful for
  telling skill from luck if it's honest. The signature is an HMAC-SHA256 over the `capstock_save`
  object, keyed from this server's `secret_key_base`, so only this server can produce a valid
  one (and a save made on a dev machine won't load in production; different secret).

  Why one canonical encoding: JSON doesn't fix key order, so the signature is computed over the
  data with every object's keys sorted. Pretty-printing or reordering the file doesn't break
  it; changing any value does.

  What's saved: cash, starting cash, positions, order history (including how each order was
  placed: manual, limit entry, take-profit or stop-loss), and open orders (entries and exits). An open exit's parent entry has already filled, but OCO finds siblings through the
  parent (`parent_id`), so the parents of open exits are saved too, as `brackets`, and recreated
  with status "filled" on import.
  """
  import Ecto.Query

  alias StockFetcher.{Repo, Tickers, Trading}
  alias StockFetcher.Trading.{Order, PendingOrder, Portfolio, Position}

  @format "capstock-save"
  @version 1
  @salt "capstock save file v1"
  # A year of heavy trading is well under this; the limit stops a huge upload tying up the LiveView.
  @max_bytes 1_000_000
  @max_orders 10_000
  @max_open 500

  @vias ["limit_entry", "take_profit", "stop_loss"]

  def max_bytes, do: @max_bytes

  @type error ::
          :invalid_file | :bad_signature | :wrong_source | :unsupported_version | :too_large

  @doc "User-facing text for an import error."
  def error_message(:invalid_file), do: "That isn't a Capstock save file (or it's damaged)."

  def error_message(:bad_signature),
    do: "This save file was edited or made by a different Capstock server, so it can't be loaded."

  def error_message(:wrong_source),
    do: "This save is for the other price source. Switch between live and mock prices to load it."

  def error_message(:unsupported_version),
    do: "This save file is from a newer version of Capstock."

  def error_message(:too_large), do: "That file is too large to be a Capstock save."

  @doc "Exports a portfolio as the save file's JSON text (pretty-printed)."
  def export(portfolio_id, source) when source in [:live, :mock] do
    portfolio = Trading.get_portfolio!(portfolio_id)
    open = Trading.list_pending_orders(portfolio_id) |> Enum.reverse()
    parent_ids = open |> Enum.map(& &1.parent_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    parents = Repo.all(from(p in PendingOrder, where: p.id in ^parent_ids, order_by: p.id))

    data = %{
      "format" => @format,
      "version" => @version,
      "source" => Atom.to_string(source),
      "saved_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "starting_cash_cents" => Trading.starting_cash(portfolio),
      "cash_cents" => portfolio.cash_cents,
      "positions" =>
        Enum.map(portfolio.positions, fn p ->
          %{"ticker" => p.ticker, "quantity" => p.quantity, "avg_cost_cents" => p.avg_cost_cents}
        end),
      "orders" =>
        portfolio_id
        |> Trading.list_orders()
        |> Enum.reverse()
        |> Enum.map(fn o ->
          %{
            "ticker" => o.ticker,
            "side" => o.side,
            "quantity" => o.quantity,
            "price_cents" => o.price_cents,
            "total_cents" => o.total_cents,
            "via" => o.via,
            "at" => iso(o.inserted_at)
          }
        end),
      "brackets" => Enum.map(parents, &pending_map/1),
      "open_orders" => Enum.map(open, &pending_map/1)
    }

    Jason.encode!(
      %{
        "about" =>
          "Capstock paper-trading save. Readable, but signed: editing it makes Capstock refuse to load it.",
        "capstock_save" => data,
        "signature" => sign(data)
      },
      pretty: true
    )
  end

  @doc """
  Imports a save file's text into a new session portfolio for `source`. Returns
  `{:ok, portfolio}` or `{:error, reason}` (see `error_message/1`). Nothing is written unless
  the whole file is valid.
  """
  def import(text, source) when is_binary(text) and source in [:live, :mock] do
    with :ok <- check_size(text),
         {:ok, %{"capstock_save" => data, "signature" => signature}} when is_map(data) <-
           decode(text),
         :ok <- verify(data, signature),
         :ok <- check_header(data, source),
         {:ok, save} <- validate(data) do
      Repo.transaction(fn -> restore!(save, source) end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_file}
    end
  end

  def import(_text, _source), do: {:error, :invalid_file}

  # --- Signing ---

  defp sign(data) do
    mac = :crypto.mac(:hmac, :sha256, key(), canonical(data))
    "hmac-sha256:" <> Base.encode16(mac, case: :lower)
  end

  defp verify(data, "hmac-sha256:" <> _ = signature) do
    if Plug.Crypto.secure_compare(sign(data), signature), do: :ok, else: {:error, :bad_signature}
  end

  defp verify(_data, _signature), do: {:error, :bad_signature}

  defp key do
    StockFetcherWeb.Endpoint.config(:secret_key_base)
    |> Plug.Crypto.KeyGenerator.generate(@salt)
  end

  # JSON with every object's keys sorted, so the signed bytes don't depend on key order.
  defp canonical(term), do: term |> sorted() |> Jason.encode!()

  defp sorted(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> {k, sorted(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp sorted(list) when is_list(list), do: Enum.map(list, &sorted/1)
  defp sorted(other), do: other

  # --- Validation (after the signature, so this mostly guards against our own bugs) ---

  defp check_size(text) when byte_size(text) <= @max_bytes, do: :ok
  defp check_size(_text), do: {:error, :too_large}

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_file}
    end
  end

  defp check_header(%{"format" => @format, "version" => @version, "source" => source}, wanted) do
    if source == Atom.to_string(wanted), do: :ok, else: {:error, :wrong_source}
  end

  defp check_header(%{"format" => @format, "version" => v}, _)
       when is_integer(v) and v > @version,
       do: {:error, :unsupported_version}

  defp check_header(_data, _wanted), do: {:error, :invalid_file}

  defp validate(data) do
    with {:ok, cash} <- non_negative(data["cash_cents"]),
         {:ok, start} <- non_negative(data["starting_cash_cents"]),
         {:ok, positions} <- all(data["positions"], 100, &position/1),
         {:ok, orders} <- all(data["orders"], @max_orders, &order/1),
         {:ok, brackets} <- all(data["brackets"], @max_open, &pending/1),
         {:ok, open} <- all(data["open_orders"], @max_open, &pending/1),
         :ok <- parents_known(open, brackets) do
      {:ok,
       %{
         cash: cash,
         start: start,
         positions: positions,
         orders: orders,
         brackets: brackets,
         open: open
       }}
    else
      _ -> {:error, :invalid_file}
    end
  end

  defp all(list, max, fun) when is_list(list) and length(list) <= max do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  defp all(_list, _max, _fun), do: :error

  defp position(%{"ticker" => t, "quantity" => q, "avg_cost_cents" => avg})
       when is_integer(q) and q != 0 and is_integer(avg) and avg > 0 do
    if Tickers.known?(t), do: {:ok, %{ticker: t, quantity: q, avg_cost_cents: avg}}, else: :error
  end

  defp position(_), do: :error

  defp order(%{"ticker" => t, "side" => side, "quantity" => q, "price_cents" => p} = o)
       when side in ["buy", "sell", "short", "cover"] and is_integer(q) and q > 0 and
              is_integer(p) and p > 0 and is_integer(:erlang.map_get("total_cents", o)) do
    # "via" is optional: saves from before it existed load as manual orders.
    with true <- Tickers.known?(t),
         {:ok, at} <- parse_time(o["at"]),
         true <- o["via"] in [nil | @vias] do
      {:ok,
       %{
         ticker: t,
         side: side,
         quantity: q,
         price_cents: p,
         total_cents: o["total_cents"],
         via: o["via"],
         inserted_at: at
       }}
    else
      _ -> :error
    end
  end

  defp order(_), do: :error

  defp pending(
         %{"ref" => ref, "type" => type, "side" => side, "ticker" => t, "quantity" => q} = p
       )
       when is_integer(ref) and type in ["limit", "stop"] and
              side in ["buy", "sell", "short", "cover"] and is_integer(q) and q > 0 do
    with true <- Tickers.known?(t),
         {:ok, trigger} <- positive(p["trigger_cents"]),
         {:ok, stop} <- optional_positive(p["stop_cents"]),
         {:ok, take_profit} <- optional_positive(p["take_profit_cents"]),
         true <- is_nil(p["parent_ref"]) or is_integer(p["parent_ref"]) do
      {:ok,
       %{
         ref: ref,
         parent_ref: p["parent_ref"],
         type: type,
         side: side,
         ticker: t,
         quantity: q,
         trigger_cents: trigger,
         stop_cents: stop,
         take_profit_cents: take_profit
       }}
    else
      _ -> :error
    end
  end

  defp pending(_), do: :error

  # Every open exit's parent must be among the saved brackets.
  defp parents_known(open, brackets) do
    refs = MapSet.new(brackets, & &1.ref)
    if Enum.all?(open, &(is_nil(&1.parent_ref) or &1.parent_ref in refs)), do: :ok, else: :error
  end

  defp non_negative(n) when is_integer(n) and n >= 0, do: {:ok, n}
  defp non_negative(_), do: :error
  defp positive(n) when is_integer(n) and n > 0, do: {:ok, n}
  defp positive(_), do: :error
  defp optional_positive(nil), do: {:ok, nil}
  defp optional_positive(n), do: positive(n)

  defp parse_time(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _} -> {:ok, DateTime.truncate(at, :second)}
      _ -> :error
    end
  end

  defp parse_time(_), do: :error

  # --- Restore ---

  defp restore!(save, source) do
    %Portfolio{id: id} = Trading.insert_session_portfolio!(source, save.cash, save.start)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      Position,
      Enum.map(
        save.positions,
        &Map.merge(&1, %{portfolio_id: id, inserted_at: now, updated_at: now})
      )
    )

    # Chunked: SQLite caps the number of bound parameters in one statement.
    save.orders
    |> Enum.map(&Map.put(&1, :portfolio_id, id))
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all(Order, &1))

    parent_ids =
      Map.new(save.brackets, fn b -> {b.ref, insert_pending!(b, id, source, "filled", nil).id} end)

    Enum.each(save.open, fn o ->
      insert_pending!(o, id, source, "open", o.parent_ref && Map.fetch!(parent_ids, o.parent_ref))
    end)

    Trading.get_portfolio!(id)
  end

  defp insert_pending!(p, portfolio_id, source, status, parent_id) do
    Repo.insert!(%PendingOrder{
      portfolio_id: portfolio_id,
      source: Atom.to_string(source),
      ticker: p.ticker,
      type: p.type,
      side: p.side,
      quantity: p.quantity,
      trigger_cents: p.trigger_cents,
      stop_cents: p.stop_cents,
      take_profit_cents: p.take_profit_cents,
      status: status,
      parent_id: parent_id
    })
  end

  defp pending_map(%PendingOrder{} = p) do
    %{
      "ref" => p.id,
      "parent_ref" => p.parent_id,
      "type" => p.type,
      "side" => p.side,
      "ticker" => p.ticker,
      "quantity" => p.quantity,
      "trigger_cents" => p.trigger_cents,
      "stop_cents" => p.stop_cents,
      "take_profit_cents" => p.take_profit_cents
    }
  end

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp iso(%NaiveDateTime{} = at), do: NaiveDateTime.to_iso8601(at) <> "Z"
end
