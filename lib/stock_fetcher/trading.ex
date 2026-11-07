defmodule StockFetcher.Trading do
  @moduledoc """
  Paper trading (PLAN.md step C): one shared module that both UIs call.

  LiveView calls it from `handle_event/3`; React will reach it through an API endpoint (step F).
  Market orders only. Limit and stop orders (step G) will build on this module.

  Rules:
    * Money is integer cents and quantities are whole shares. Prices arrive as floats (the
      `stock_prices.price` column is a float), so they are converted to cents exactly once, at
      the boundary, through `Decimal`.
    * This module never fetches prices. The caller passes the latest known price for the
      ticker, or `nil` when there is none (reported as `:unknown_ticker`). Where that price
      comes from is a step D (process design) decision.
    * Concurrent orders on one portfolio are safe: the first statement of each transaction is
      a conditional `UPDATE` (`... WHERE cash_cents >= total`), so the check and the change
      happen in one atomic step, and SQLite's single writer serializes the rest.
    * Live orders only fill while the market is open (`MarketHours.market_open?/1`). After
      hours the Worker stops polling, so the newest price is the last one before the close and
      filling at it would be trading on a stale price. Mock orders are exempt: mock prices are
      simulated and always moving, and the mock demo is most useful after hours.
  """
  import Ecto.Query

  alias StockFetcher.{MarketHours, Repo}
  alias StockFetcher.Trading.{Order, PendingOrder, Portfolio, Position}

  # Assumptions until John answers questions 1 and 3 (PLAN.md section 2): one shared demo
  # portfolio, $100,000 starting cash (his example position was $60,000).
  # One demo portfolio per price source, so mock trades (made-up prices on the same tickers)
  # never mix with positions bought at real prices.
  @demo_names %{live: "demo", mock: "demo-mock"}
  @starting_cash_cents 10_000_000

  @type error ::
          :invalid_side
          | :invalid_quantity
          | :invalid_price
          | :unknown_ticker
          | :portfolio_not_found
          | :insufficient_cash
          | :insufficient_shares
          | :market_closed
          | :invalid_limit
          | :invalid_stop
          | :not_open

  def starting_cash_cents, do: @starting_cash_cents

  @doc """
  Returns the demo portfolio for a price source (with positions), creating it on first use.
  `:live` (default) is the real-price portfolio; `:mock` is a separate sandbox for the mock
  stream.
  """
  def demo_portfolio(source \\ :live) do
    name = Map.fetch!(@demo_names, source)

    # on_conflict: :nothing makes concurrent first calls safe: only one row is ever created.
    Repo.insert!(%Portfolio{name: name, cash_cents: @starting_cash_cents},
      on_conflict: :nothing,
      conflict_target: :name
    )

    Portfolio |> Repo.get_by!(name: name) |> Repo.preload(:positions)
  end

  @doc "Fetches a portfolio with its positions (sorted by ticker). Raises if it doesn't exist."
  def get_portfolio!(id), do: Portfolio |> Repo.get!(id) |> Repo.preload(:positions)

  @doc "Lists a portfolio's filled orders, newest first."
  def list_orders(portfolio_id) do
    Repo.all(
      from(o in Order,
        where: o.portfolio_id == ^portfolio_id,
        order_by: [desc: o.id]
      )
    )
  end

  @doc """
  Fills a market order immediately at `price`.

  `side` is `"buy"`/`"sell"` (or the atoms). `quantity` may be an integer or a string from a
  form or JSON body. `price` is the latest known price in dollars (float, integer, or
  `Decimal`), or `nil` if the ticker has no price.

  Options:
    * `:source` - `:live` (default) or `:mock`. Live orders are rejected with
      `:market_closed` outside market hours; mock orders are not.
    * `:now` - the current time, for tests (default: `now/0`).

  Returns `{:ok, %{order: order, portfolio: portfolio}}` (portfolio reloaded with positions) or
  `{:error, reason}`; see `error_message/1` for user-facing text.
  """
  @spec place_market_order(integer(), term(), term(), term(), term(), keyword()) ::
          {:ok, %{order: Order.t(), portfolio: Portfolio.t()}} | {:error, error()}
  def place_market_order(portfolio_id, side, ticker, quantity, price, opts \\ []) do
    source = Keyword.get(opts, :source, :live)
    now = Keyword.get_lazy(opts, :now, &now/0)

    with {:ok, side} <- normalize_side(side),
         {:ok, ticker} <- normalize_ticker(ticker),
         {:ok, quantity} <- normalize_quantity(quantity),
         :ok <- check_market_hours(source, now),
         {:ok, price_cents} <- to_cents(price),
         {:ok, order} <-
           Repo.transaction(fn -> fill(side, portfolio_id, ticker, quantity, price_cents) end) do
      {:ok, %{order: order, portfolio: get_portfolio!(portfolio_id)}}
    end
  end

  @doc "User-facing text for an error reason. Both UIs show the same messages (benchmark spec)."
  def error_message(:insufficient_cash), do: "Insufficient cash for this order."
  def error_message(:insufficient_shares), do: "You can't sell more shares than you hold."
  def error_message(:unknown_ticker), do: "Unknown ticker: no price available."
  def error_message(:invalid_quantity), do: "Quantity must be a whole number greater than 0."
  def error_message(:invalid_side), do: "Side must be buy or sell."
  def error_message(:invalid_price), do: "No valid price for this ticker."
  def error_message(:portfolio_not_found), do: "Portfolio not found."

  def error_message(:market_closed),
    do: "Market is closed. Orders fill Mon-Fri, 9:30 AM-4:00 PM ET."

  def error_message(:invalid_limit), do: "Limit price must be a number greater than 0."

  def error_message(:invalid_stop),
    do: "Stop price must be greater than 0 and below the limit price."

  def error_message(:not_open), do: "This order is no longer open (it may have just filled)."

  # --- Resting orders (step G): limit buy entries and their stop-losses ---

  @doc """
  Decides whether a resting order fills at a tick price (integer cents), and at what price.
  Strict on purpose, so paper results don't flatter John (LOG.md 2026-11-06):

    * limit buy: only when the price trades *through* the limit (strictly below it), filled
      at the limit price. A touch isn't enough: in a real market other orders at that price
      may be ahead in the queue.
    * stop sell: when the price is at or below the stop, filled at that tick's price, which
      can be worse than the stop if the price gapped between ticks.

  Returns `{:fill, price_cents}` or `:wait`.
  """
  @spec fill_rule(PendingOrder.t(), integer()) :: {:fill, integer()} | :wait

  def fill_rule(%PendingOrder{type: "limit", trigger_cents: limit}, price_cents)
      when price_cents < limit do
    {:fill, limit}
  end

  def fill_rule(%PendingOrder{type: "stop", trigger_cents: stop}, price_cents)
      when price_cents <= stop do
    {:fill, price_cents}
  end

  def fill_rule(%PendingOrder{}, _price_cents), do: :wait

  @doc """
  Places a limit buy entry, with an optional stop-loss created when it fills.

  `limit_price`/`stop_price` may be numbers or strings from a form (`stop_price` blank or nil
  for no stop). Options:
    * `:source` - `:live` (default) or `:mock`: which price stream may trigger it.
    * `:current_price` - the latest price the user saw (dollars). If it's already below the
      limit and the market is open, the order fills now at that price, as a real exchange
      would: there's a seller below the limit right now.
    * `:now` - the current time, for tests.

  Returns `{:ok, :placed, pending}`, `{:ok, :filled, fill}` (see `fill_pending_order/2`), or
  `{:error, reason}`.
  """
  def place_limit_order(portfolio_id, ticker, quantity, limit_price, stop_price, opts \\ []) do
    source = Keyword.get(opts, :source, :live)
    now = Keyword.get_lazy(opts, :now, &now/0)

    with {:ok, ticker} <- normalize_ticker(ticker),
         {:ok, quantity} <- normalize_quantity(quantity),
         {:ok, limit_cents} <- input_cents(limit_price, :invalid_limit),
         {:ok, stop_cents} <- stop_cents(stop_price, limit_cents),
         {:ok, pending} <-
           insert_pending(%PendingOrder{
             portfolio_id: portfolio_id,
             source: Atom.to_string(source),
             ticker: ticker,
             type: "limit",
             side: "buy",
             quantity: quantity,
             trigger_cents: limit_cents,
             stop_cents: stop_cents
           }) do
      maybe_fill_now(pending, Keyword.get(opts, :current_price), source, now)
    end
  end

  @doc """
  Fills an open resting order at `fill_cents`, in one transaction:
  claims it (`open` -> `filled`, conditional), moves cash and shares through the same code as
  market orders, and, for a limit entry with a stop, creates the open stop-loss sell.

  Returns `{:ok, %{order: order, pending: pending, stop: stop_or_nil}}`,
  `{:error, :not_open}` if it was already cancelled or filled, or `{:error, reason}` if the
  fill failed (e.g. `:insufficient_cash`), in which case the order is marked "rejected".
  """
  def fill_pending_order(pending_id, fill_cents) when is_integer(fill_cents) and fill_cents > 0 do
    result =
      Repo.transaction(fn ->
        # First statement: the conditional claim. Whichever of cancel and fill runs first wins;
        # the other matches 0 rows (same pattern as buy/5's cash check).
        pending = claim!(pending_id)

        order =
          fill(pending.side, pending.portfolio_id, pending.ticker, pending.quantity, fill_cents)

        pending = pending |> Ecto.Changeset.change(order_id: order.id) |> Repo.update!()
        %{order: order, pending: pending, stop: maybe_insert_stop(pending)}
      end)

    case result do
      {:error, reason} when reason in [:insufficient_cash, :insufficient_shares] ->
        reject(pending_id, reason)
        {:error, reason}

      other ->
        other
    end
  end

  @doc "Cancels an open resting order of this portfolio. `{:error, :not_open}` if it isn't open."
  def cancel_pending_order(portfolio_id, pending_id) do
    with {:ok, id} <- to_id(pending_id),
         {1, _} <-
           from(p in PendingOrder,
             where: p.id == ^id and p.portfolio_id == ^portfolio_id and p.status == "open"
           )
           |> Repo.update_all(set: [status: "cancelled", updated_at: utc_now()]) do
      {:ok, Repo.get!(PendingOrder, id)}
    else
      _ -> {:error, :not_open}
    end
  end

  @doc "Open resting orders that a tick for `ticker` from `source` (\"live\"/\"mock\") could fill."
  def list_open_orders(source, ticker) do
    Repo.all(
      from(p in PendingOrder,
        where: p.source == ^source and p.ticker == ^ticker and p.status == "open",
        order_by: p.id
      )
    )
  end

  @doc "A portfolio's open resting orders, newest first."
  def list_pending_orders(portfolio_id) do
    Repo.all(
      from(p in PendingOrder,
        where: p.portfolio_id == ^portfolio_id and p.status == "open",
        order_by: [desc: p.id]
      )
    )
  end

  @doc ~S'Short description, e.g. "limit buy 3 AAPL at $190.00, stop $177.00".'
  def describe(%PendingOrder{type: "limit"} = p) do
    stop = if p.stop_cents, do: ", stop #{format_cents(p.stop_cents)}", else: ""
    "limit buy #{p.quantity} #{p.ticker} at #{format_cents(p.trigger_cents)}#{stop}"
  end

  def describe(%PendingOrder{type: "stop"} = p),
    do: "stop-loss sell #{p.quantity} #{p.ticker} at #{format_cents(p.trigger_cents)}"

  @doc "PubSub topic for a portfolio's resting-order events (OrderWatcher -> PricesLive)."
  def portfolio_topic(portfolio_id), do: "portfolio:#{portfolio_id}"

  @doc """
  Confirmation text for a filled order, e.g. "Bought 3 AAPL at $190.00 ($570.00)".
  Lives here, not in a UI, so the LiveView and React panels show the same text (benchmark spec).
  """
  @spec confirmation(Order.t()) :: String.t()
  def confirmation(%Order{} = order) do
    verb = if order.side == "buy", do: "Bought", else: "Sold"

    "#{verb} #{order.quantity} #{order.ticker} at #{format_cents(order.price_cents)} " <>
      "(#{format_cents(order.total_cents)})"
  end

  @doc ~S'Formats integer cents as dollars: 1234567 -> "$12,345.67", -500 -> "-$5.00".'
  @spec format_cents(integer()) :: String.t()
  def format_cents(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    dollars = cents |> abs() |> div(100) |> Integer.to_string()
    dollars = Regex.replace(~r/\B(?=(\d{3})+(?!\d))/, dollars, ",")
    pennies = cents |> abs() |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}$#{dollars}.#{pennies}"
  end

  # --- Market hours ---

  # Live prices stop updating after the close, so live orders only fill while the market
  # is open.
  defp check_market_hours(:mock, _now), do: :ok

  defp check_market_hours(:live, now) do
    if MarketHours.market_open?(now) do
      :ok
    else
      {:error, :market_closed}
    end
  end

  # The real clock, unless config/test.exs pins one (`:trading_fixed_now`) so tests that place
  # orders don't fail when run after hours. Unset in dev and prod.
  defp now, do: Application.get_env(:stock_fetcher, :trading_fixed_now) || DateTime.utc_now()

  # --- Resting-order internals ---

  defp insert_pending(%PendingOrder{} = pending), do: {:ok, Repo.insert!(pending)}

  # Already marketable and the market is open: fill now at the price the user saw.
  defp maybe_fill_now(pending, current_price, source, now) do
    with {:ok, current_cents} <- to_cents(current_price),
         true <- current_cents < pending.trigger_cents,
         :ok <- check_market_hours(source, now) do
      case fill_pending_order(pending.id, current_cents) do
        {:ok, fill} -> {:ok, :filled, fill}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:ok, :placed, pending}
    end
  end

  defp claim!(id) do
    {claimed, _} =
      from(p in PendingOrder, where: p.id == ^id and p.status == "open")
      |> Repo.update_all(set: [status: "filled", updated_at: utc_now()])

    if claimed == 0, do: Repo.rollback(:not_open)
    Repo.get!(PendingOrder, id)
  end

  defp maybe_insert_stop(%PendingOrder{type: "limit", stop_cents: stop} = entry)
       when is_integer(stop) do
    Repo.insert!(%PendingOrder{
      portfolio_id: entry.portfolio_id,
      source: entry.source,
      ticker: entry.ticker,
      type: "stop",
      side: "sell",
      quantity: entry.quantity,
      trigger_cents: stop,
      parent_id: entry.id
    })
  end

  defp maybe_insert_stop(_), do: nil

  # Conditional too: if it was cancelled meanwhile, it stays cancelled.
  defp reject(id, reason) do
    from(p in PendingOrder, where: p.id == ^id and p.status == "open")
    |> Repo.update_all(
      set: [status: "rejected", reject_reason: Atom.to_string(reason), updated_at: utc_now()]
    )
  end

  defp stop_cents(blank, _limit_cents) when blank in [nil, ""], do: {:ok, nil}

  defp stop_cents(stop_price, limit_cents) do
    case input_cents(stop_price, :invalid_stop) do
      {:ok, stop} when stop < limit_cents -> {:ok, stop}
      _ -> {:error, :invalid_stop}
    end
  end

  # Prices typed into a form arrive as strings ("190.5"); numbers come from code and tests.
  defp input_cents(value, error) when is_binary(value) do
    case value |> String.trim() |> Decimal.parse() do
      {decimal, ""} -> input_cents(decimal, error)
      _ -> {:error, error}
    end
  end

  defp input_cents(value, error) do
    case to_cents(value) do
      {:ok, cents} -> {:ok, cents}
      {:error, _} -> {:error, error}
    end
  end

  defp to_id(id) when is_integer(id), do: {:ok, id}

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp to_id(_), do: :error

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # --- Fills (run inside Repo.transaction/1) ---

  # One clause per side instead of a `case`, which keeps place_market_order/5 shallow.
  defp fill("buy", portfolio_id, ticker, quantity, price_cents),
    do: buy(portfolio_id, ticker, quantity, price_cents, quantity * price_cents)

  defp fill("sell", portfolio_id, ticker, quantity, price_cents),
    do: sell(portfolio_id, ticker, quantity, price_cents, quantity * price_cents)

  defp buy(portfolio_id, ticker, quantity, price_cents, total_cents) do
    # Check-and-debit in one statement. Doing the write first also takes SQLite's write lock
    # at the start of the transaction, so the reads below can't go stale.
    {debited, _} =
      from(p in Portfolio, where: p.id == ^portfolio_id and p.cash_cents >= ^total_cents)
      |> Repo.update_all(inc: [cash_cents: -total_cents])

    if debited == 0 do
      Repo.rollback(
        if Repo.get(Portfolio, portfolio_id), do: :insufficient_cash, else: :portfolio_not_found
      )
    end

    case Repo.get_by(Position, portfolio_id: portfolio_id, ticker: ticker) do
      nil ->
        Repo.insert!(%Position{
          portfolio_id: portfolio_id,
          ticker: ticker,
          quantity: quantity,
          avg_cost_cents: price_cents
        })

      position ->
        new_quantity = position.quantity + quantity
        cost_cents = position.quantity * position.avg_cost_cents + total_cents

        position
        |> Ecto.Changeset.change(
          quantity: new_quantity,
          # Integer division rounded half up, so the average stays in whole cents.
          avg_cost_cents: div(cost_cents + div(new_quantity, 2), new_quantity)
        )
        |> Repo.update!()
    end

    insert_order(portfolio_id, "buy", ticker, quantity, price_cents, total_cents)
  end

  defp sell(portfolio_id, ticker, quantity, price_cents, total_cents) do
    {reduced, _} =
      from(p in Position,
        where: p.portfolio_id == ^portfolio_id and p.ticker == ^ticker and p.quantity >= ^quantity
      )
      |> Repo.update_all(inc: [quantity: -quantity])

    if reduced == 0, do: Repo.rollback(:insufficient_shares)

    from(p in Portfolio, where: p.id == ^portfolio_id)
    |> Repo.update_all(inc: [cash_cents: total_cents])

    # A fully closed position is removed rather than kept at 0 shares.
    from(p in Position,
      where: p.portfolio_id == ^portfolio_id and p.ticker == ^ticker and p.quantity == 0
    )
    |> Repo.delete_all()

    insert_order(portfolio_id, "sell", ticker, quantity, price_cents, total_cents)
  end

  defp insert_order(portfolio_id, side, ticker, quantity, price_cents, total_cents) do
    Repo.insert!(%Order{
      portfolio_id: portfolio_id,
      side: side,
      ticker: ticker,
      quantity: quantity,
      price_cents: price_cents,
      total_cents: total_cents
    })
  end

  # --- Input normalization (both UIs send strings) ---

  defp normalize_side(side) when side in ["buy", :buy], do: {:ok, "buy"}
  defp normalize_side(side) when side in ["sell", :sell], do: {:ok, "sell"}
  defp normalize_side(_), do: {:error, :invalid_side}

  defp normalize_ticker(ticker) when is_binary(ticker) do
    case ticker |> String.trim() |> String.upcase() do
      "" -> {:error, :unknown_ticker}
      ticker -> {:ok, ticker}
    end
  end

  defp normalize_ticker(_), do: {:error, :unknown_ticker}

  defp normalize_quantity(quantity) when is_integer(quantity) and quantity > 0,
    do: {:ok, quantity}

  defp normalize_quantity(quantity) when is_binary(quantity) do
    case Integer.parse(String.trim(quantity)) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_quantity}
    end
  end

  defp normalize_quantity(_), do: {:error, :invalid_quantity}

  defp to_cents(nil), do: {:error, :unknown_ticker}
  defp to_cents(price) when is_float(price), do: price |> Decimal.from_float() |> to_cents()
  defp to_cents(price) when is_integer(price), do: price |> Decimal.new() |> to_cents()

  # Decimal avoids float artifacts such as 189.57 * 100 == 18956.999999999996.
  defp to_cents(%Decimal{} = price) do
    cents = price |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()
    if cents > 0, do: {:ok, cents}, else: {:error, :invalid_price}
  end

  defp to_cents(_), do: {:error, :invalid_price}
end
