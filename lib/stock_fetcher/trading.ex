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
  alias StockFetcher.Trading.{Order, Portfolio, Position}

  # Assumptions until John answers questions 1 and 3 (PLAN.md section 2): one shared demo
  # portfolio, $100,000 starting cash (his example position was $60,000).
  @demo_name "demo"
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

  def starting_cash_cents, do: @starting_cash_cents

  @doc "Returns the shared demo portfolio (with positions), creating it on first use."
  def demo_portfolio do
    # on_conflict: :nothing makes concurrent first calls safe: only one row is ever created.
    Repo.insert!(%Portfolio{name: @demo_name, cash_cents: @starting_cash_cents},
      on_conflict: :nothing,
      conflict_target: :name
    )

    Portfolio |> Repo.get_by!(name: @demo_name) |> Repo.preload(:positions)
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
