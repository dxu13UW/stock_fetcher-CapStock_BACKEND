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
    * Four sides. `"buy"`/`"sell"` are the benchmark (both UIs). `"short"`/`"cover"` are
      LiveView-only: a short sells shares you don't own and a cover buys them back. A short is
      cash-secured: its full value is set aside from cash (no leverage), and the cover returns
      that collateral plus or minus the P/L. A position is never long and short at once: Buy
      on a short and Short on a long are refused, so each side keeps one meaning.
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
          | :invalid_take_profit
          | :invalid_direction
          | :invalid_trigger
          | :would_fill_now
          | :short_open
          | :long_open
          | :insufficient_short
          | :not_open
          | :invalid_starting_cash

  # Which way an order trades. Used in guards, so fill_rule/2 reads as the 2x2 table it is.
  @buying ["buy", "cover"]
  @selling ["sell", "short"]

  # Fill failures that mark a resting order "rejected" (the state changed since it was placed,
  # e.g. cash spent elsewhere). It isn't retried on the next tick.
  @rejections [:insufficient_cash, :insufficient_shares, :insufficient_short] ++
                [:short_open, :long_open, :portfolio_not_found]

  # Buying power a user may start a session portfolio with (2026-11-07): $1,000 to $2,000,000.
  @min_starting_cash_cents 100_000
  @max_starting_cash_cents 200_000_000

  def starting_cash_cents, do: @starting_cash_cents
  def starting_cash_range, do: {@min_starting_cash_cents, @max_starting_cash_cents}

  @doc """
  Creates a private portfolio for one LiveView tab (2026-11-07). `starting_cash` is dollars
  (a form string such as "250000" or "250,000.50", or a number), between $1,000 and $2,000,000.

  Nobody else can reach it: its id lives only in that tab's LiveView process (never in a URL
  or cookie), so there is nothing for another visitor to guess or share. It is deleted when the
  tab closes; the user keeps their progress in a save file (`Trading.SaveFile`).
  """
  def create_session_portfolio(source, starting_cash \\ @starting_cash_cents / 100)
      when source in [:live, :mock] do
    with {:ok, cents} <- starting_cash_cents(starting_cash) do
      {:ok, insert_session_portfolio!(source, cents, cents)}
    end
  end

  @doc false
  # Shared with SaveFile, which restores a cash balance different from the starting amount.
  def insert_session_portfolio!(source, cash_cents, starting_cash_cents) do
    name =
      "session:#{source}:" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    Repo.insert!(%Portfolio{
      name: name,
      cash_cents: cash_cents,
      starting_cash_cents: starting_cash_cents
    })
    |> Repo.preload(:positions)
  end

  @doc "True for a per-tab session portfolio (see `create_session_portfolio/2`)."
  def session_portfolio?(%Portfolio{name: "session:" <> _}), do: true
  def session_portfolio?(_), do: false

  @doc """
  Deletes a portfolio with its positions, orders and resting orders (the foreign keys cascade).
  Only session portfolios: the shared demo ones belong to the React SPA too.
  """
  def delete_session_portfolio(id) do
    {count, _} =
      Repo.delete_all(from(p in Portfolio, where: p.id == ^id and like(p.name, "session:%")))

    count
  end

  @doc "Deletes every session portfolio. Run once at boot: no tab survives a restart."
  def delete_all_session_portfolios do
    {count, _} = Repo.delete_all(from(p in Portfolio, where: like(p.name, "session:%")))
    count
  end

  @doc """
  What a portfolio is worth at the given prices, in cents: cash, plus each long position at its
  price, plus what covering each short would return (its collateral, `qty x avg`, plus the P/L,
  `qty x (avg - price)`), which is the same `qty x (2 x avg - price)` that `cover/5` credits.
  `price_fun` returns a ticker's price in cents or nil; a position without a price counts at its
  average cost. Display only.
  """
  def account_value_cents(%Portfolio{cash_cents: cash, positions: positions}, price_fun) do
    Enum.reduce(positions, cash, fn pos, acc ->
      price = price_fun.(pos.ticker) || pos.avg_cost_cents

      if pos.quantity > 0,
        do: acc + pos.quantity * price,
        else: acc + -pos.quantity * (2 * pos.avg_cost_cents - price)
    end)
  end

  @doc "A portfolio's starting cash; the old demo portfolios predate the column."
  def starting_cash(%Portfolio{starting_cash_cents: nil}), do: @starting_cash_cents
  def starting_cash(%Portfolio{starting_cash_cents: cents}), do: cents

  defp starting_cash_cents(value) when is_binary(value) do
    case value |> String.replace([",", "$", " "], "") |> Decimal.parse() do
      {decimal, ""} -> starting_cash_cents(decimal)
      _ -> {:error, :invalid_starting_cash}
    end
  end

  defp starting_cash_cents(value) when is_float(value),
    do: value |> Decimal.from_float() |> starting_cash_cents()

  defp starting_cash_cents(value) when is_integer(value),
    do: value |> Decimal.new() |> starting_cash_cents()

  defp starting_cash_cents(%Decimal{} = dollars) do
    cents = dollars |> Decimal.mult(100) |> Decimal.round(0, :down) |> Decimal.to_integer()

    if cents in @min_starting_cash_cents..@max_starting_cash_cents,
      do: {:ok, cents},
      else: {:error, :invalid_starting_cash}
  end

  defp starting_cash_cents(_), do: {:error, :invalid_starting_cash}

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

  def error_message(:invalid_starting_cash),
    do: "Starting buying power must be between $1,000 and $2,000,000."

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
    do: "Stop price must be past the limit: below it for a long, above it for a short."

  def error_message(:invalid_take_profit),
    do: "Take-profit must be beyond the limit: above it for a long, below it for a short."

  def error_message(:invalid_direction), do: "Direction must be long or short."
  def error_message(:invalid_trigger), do: "New price must be a number greater than 0."

  def error_message(:would_fill_now),
    do: "That price is already past the market, so it would fill now. Use Sell or Cover to exit."

  def error_message(:short_open),
    do: "You're short this ticker. Cover the short before buying."

  def error_message(:long_open), do: "You hold this ticker. Sell it before shorting."
  def error_message(:insufficient_short), do: "You can't cover more shares than you're short."
  def error_message(:not_open), do: "This order is no longer open (it may have just filled)."

  # --- Resting orders: limit entries (long or short) and their exits ---

  @doc """
  Decides whether a resting order fills at a tick price (integer cents), and at what price.
  Strict on purpose, so paper results don't flatter John (LOG.md 2026-11-06).

  The four exit scenarios are a 2x2 of direction (buying / selling) and type:

  |          | limit (guarantees the price)      | stop (guarantees the exit)           |
  |----------|-----------------------------------|--------------------------------------|
  | buying   | price < limit, fills at the limit | price >= stop, fills at the tick     |
  | selling  | price > limit, fills at the limit | price <= stop, fills at the tick     |

  A limit needs the price to trade *through* it (a touch isn't enough: other orders at that
  price may be ahead in the queue). A stop fills at the tick price, which can be worse than
  the stop if the price gapped. Long entry and short take-profit are buying limits; long
  take-profit and short entry are selling limits; long stop-loss is a selling stop and short
  stop-loss a buying stop.

  Returns `{:fill, price_cents}` or `:wait`.
  """
  @spec fill_rule(PendingOrder.t(), integer()) :: {:fill, integer()} | :wait

  def fill_rule(%PendingOrder{type: "limit", side: side, trigger_cents: limit}, price_cents)
      when side in @buying and price_cents < limit,
      do: {:fill, limit}

  def fill_rule(%PendingOrder{type: "limit", side: side, trigger_cents: limit}, price_cents)
      when side in @selling and price_cents > limit,
      do: {:fill, limit}

  def fill_rule(%PendingOrder{type: "stop", side: side, trigger_cents: stop}, price_cents)
      when side in @selling and price_cents <= stop,
      do: {:fill, price_cents}

  def fill_rule(%PendingOrder{type: "stop", side: side, trigger_cents: stop}, price_cents)
      when side in @buying and price_cents >= stop,
      do: {:fill, price_cents}

  def fill_rule(%PendingOrder{}, _price_cents), do: :wait

  @doc """
  Places a limit entry with an optional stop-loss and take-profit (a bracket), created when
  the entry fills.

  `limit_price`/`stop_price` may be numbers or strings from a form (`stop_price` blank or nil
  for no stop). Options:
    * `:direction` - `:long` (default; a limit buy below the price) or `:short` (a limit short
      above the price). Strings "long"/"short" from a form are accepted.
    * `:take_profit` - optional take-profit price (blank or nil for none).
    * `:source` - `:live` (default) or `:mock`: which price stream may trigger it.
    * `:current_price` - the latest price the user saw (dollars). If the limit is already
      marketable (a long limit above the price, a short limit below it) and the market is
      open, the order fills now at that price, as a real exchange would.
    * `:now` - the current time, for tests.

  The prices must be in order: long `stop < limit < take-profit`, short
  `take-profit < limit < stop`.

  Returns `{:ok, :placed, pending}`, `{:ok, :filled, fill}` (see `fill_pending_order/2`), or
  `{:error, reason}`.
  """
  def place_limit_order(portfolio_id, ticker, quantity, limit_price, stop_price, opts \\ []) do
    source = Keyword.get(opts, :source, :live)
    now = Keyword.get_lazy(opts, :now, &now/0)

    with {:ok, direction} <- normalize_direction(Keyword.get(opts, :direction, :long)),
         {:ok, ticker} <- normalize_ticker(ticker),
         {:ok, quantity} <- normalize_quantity(quantity),
         {:ok, limit_cents} <- input_cents(limit_price, :invalid_limit),
         {:ok, stop_cents} <- exit_cents(stop_price, limit_cents, direction, :stop),
         {:ok, tp_cents} <-
           exit_cents(Keyword.get(opts, :take_profit), limit_cents, direction, :take_profit),
         {:ok, pending} <-
           insert_pending(%PendingOrder{
             portfolio_id: portfolio_id,
             source: Atom.to_string(source),
             ticker: ticker,
             type: "limit",
             side: entry_side(direction),
             quantity: quantity,
             trigger_cents: limit_cents,
             stop_cents: stop_cents,
             take_profit_cents: tp_cents
           }) do
      maybe_fill_now(pending, Keyword.get(opts, :current_price), source, now)
    end
  end

  @doc """
  Fills an open resting order at `fill_cents`, in one transaction:
    1. claims it (`open` -> `filled`, conditional),
    2. moves cash and shares through the same code as market orders,
    3. for an entry, creates its exits (stop-loss and/or take-profit),
    4. for an exit, cancels the other exit of the same entry (OCO: one cancels the other).

  Returns `{:ok, %{order:, pending:, stop:, take_profit:, cancelled:}}` (`stop`/`take_profit`
  are the new exits or nil; `cancelled` is how many sibling exits OCO cancelled),
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

        # Record how it was placed, for the order history ("take-profit", "stop-loss", ...).
        order = order |> Ecto.Changeset.change(via: via(pending)) |> Repo.update!()
        pending = pending |> Ecto.Changeset.change(order_id: order.id) |> Repo.update!()

        %{
          order: order,
          pending: pending,
          stop: maybe_insert_exit(pending, :stop),
          take_profit: maybe_insert_exit(pending, :take_profit),
          cancelled: cancel_siblings(pending)
        }
      end)

    case result do
      {:error, reason} when reason in @rejections ->
        reject(pending_id, reason)
        {:error, reason}

      other ->
        other
    end
  end

  defp via(%PendingOrder{type: "stop"}), do: "stop_loss"
  defp via(%PendingOrder{type: "limit", parent_id: nil}), do: "limit_entry"
  defp via(%PendingOrder{type: "limit"}), do: "take_profit"

  @doc """
  Moves an open exit (a stop-loss or take-profit) to `new_price`, e.g. to raise a long's stop
  to break-even after the price ran up. Entries can't be moved; cancel and place a new one.

  `:current_price` (dollars) is the latest price the user saw. If the new price is already
  past it, the exit would fill at once, which is almost always a typo, so it's refused with
  `:would_fill_now`. This reuses `fill_rule/2`: "would this order fill at the current price?"

  Moving a stop further away (more risk) is allowed, as at a real broker; the simulator shows
  the consequences rather than forbidding them.

  Returns `{:ok, pending}` or `{:error, reason}`. The update is conditional on the order still
  being open, so a move and a fill can't both win.
  """
  def amend_order(portfolio_id, pending_id, new_price, opts \\ []) do
    with {:ok, id} <- to_id(pending_id),
         %PendingOrder{} = order <- get_open_exit(portfolio_id, id),
         {:ok, cents} <- input_cents(new_price, :invalid_trigger),
         :ok <- check_not_marketable(%{order | trigger_cents: cents}, opts[:current_price]),
         {1, _} <-
           from(p in PendingOrder,
             where: p.id == ^id and p.portfolio_id == ^portfolio_id and p.status == "open"
           )
           |> Repo.update_all(set: [trigger_cents: cents, updated_at: utc_now()]) do
      {:ok, Repo.get!(PendingOrder, id)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_open}
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

  @doc """
  A portfolio's open orders grouped the way the page shows them (2026-11-07): each filled
  entry's exits together as one bracket, then the entries still waiting to fill.

    * `%{kind: :bracket, id: parent_id, ticker, quantity, direction: :long | :short,
      entry_cents: fill price or nil, exits: [PendingOrder, ...] (highest price first)}`
    * `%{kind: :entry, id: id, order: PendingOrder}`

  The exits of one bracket share a `parent_id` (that's also how OCO finds the sibling), so
  grouping by it is exact. `entry_cents` comes from the parent's fill (`parent.order`).
  Newest first within each kind.
  """
  def open_order_groups(portfolio_id) do
    {exits, entries} =
      portfolio_id
      |> list_pending_orders()
      |> Repo.preload(parent: :order)
      |> Enum.split_with(&exit?/1)

    brackets =
      exits
      |> Enum.group_by(& &1.parent_id)
      |> Enum.map(fn {parent_id, [first | _] = list} ->
        %{
          kind: :bracket,
          id: parent_id,
          ticker: first.ticker,
          quantity: first.quantity,
          # A long is closed by selling, a short by covering.
          direction: if(first.side == "sell", do: :long, else: :short),
          entry_cents: first.parent && first.parent.order && first.parent.order.price_cents,
          exits: Enum.sort_by(list, & &1.trigger_cents, :desc)
        }
      end)
      |> Enum.sort_by(& &1.id, :desc)

    brackets ++ Enum.map(entries, &%{kind: :entry, id: &1.id, order: &1})
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
  def describe(%PendingOrder{type: "limit", parent_id: nil} = p) do
    stop = if p.stop_cents, do: ", stop #{format_cents(p.stop_cents)}", else: ""

    take_profit =
      if p.take_profit_cents, do: ", take-profit #{format_cents(p.take_profit_cents)}", else: ""

    "limit #{p.side} #{p.quantity} #{p.ticker} at #{format_cents(p.trigger_cents)}" <>
      stop <> take_profit
  end

  def describe(%PendingOrder{type: "limit"} = p),
    do: "take-profit #{p.side} #{p.quantity} #{p.ticker} at #{format_cents(p.trigger_cents)}"

  def describe(%PendingOrder{type: "stop"} = p),
    do: "stop-loss #{p.side} #{p.quantity} #{p.ticker} at #{format_cents(p.trigger_cents)}"

  @doc "True for an exit (stop-loss or take-profit), which `amend_order/4` can move."
  def exit?(%PendingOrder{parent_id: parent_id}), do: not is_nil(parent_id)

  @doc "PubSub topic for a portfolio's resting-order events (OrderWatcher -> PricesLive)."
  def portfolio_topic(portfolio_id), do: "portfolio:#{portfolio_id}"

  @doc """
  Confirmation text for a filled order, e.g. "Bought 3 AAPL at $190.00 ($570.00)".
  Lives here, not in a UI, so the LiveView and React panels show the same text (benchmark spec).
  """
  @spec confirmation(Order.t()) :: String.t()
  def confirmation(%Order{} = order) do
    "#{verb(order.side)} #{order.quantity} #{order.ticker} at #{format_cents(order.price_cents)} " <>
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

  # Already marketable and the market is open: fill now at the price the user saw (a better
  # price than the limit, which is what a real exchange gives you).
  defp maybe_fill_now(pending, current_price, source, now) do
    with {:ok, current_cents} <- to_cents(current_price),
         {:fill, _limit} <- fill_rule(pending, current_cents),
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

  # An entry that just filled creates its exits. They close the position, so they trade the
  # other way: a long's exits sell, a short's exits cover. The stop is a stop order; the
  # take-profit is a limit order (see the table in fill_rule/2).
  defp maybe_insert_exit(%PendingOrder{parent_id: nil, type: "limit"} = entry, kind) do
    trigger = if kind == :stop, do: entry.stop_cents, else: entry.take_profit_cents

    if trigger do
      Repo.insert!(%PendingOrder{
        portfolio_id: entry.portfolio_id,
        source: entry.source,
        ticker: entry.ticker,
        type: if(kind == :stop, do: "stop", else: "limit"),
        side: exit_side(entry.side),
        quantity: entry.quantity,
        trigger_cents: trigger,
        parent_id: entry.id
      })
    end
  end

  defp maybe_insert_exit(_exit, _kind), do: nil

  # OCO: an exit that fills cancels the other exit of the same entry, in the same
  # transaction, so the position can't be closed twice. Conditional on "open" like every
  # status change. Returns how many were cancelled.
  defp cancel_siblings(%PendingOrder{parent_id: nil}), do: 0

  defp cancel_siblings(%PendingOrder{id: id, parent_id: parent_id}) do
    {count, _} =
      from(p in PendingOrder,
        where: p.parent_id == ^parent_id and p.id != ^id and p.status == "open"
      )
      |> Repo.update_all(set: [status: "cancelled", updated_at: utc_now()])

    count
  end

  defp get_open_exit(portfolio_id, id) do
    Repo.one(
      from(p in PendingOrder,
        where:
          p.id == ^id and p.portfolio_id == ^portfolio_id and p.status == "open" and
            not is_nil(p.parent_id)
      )
    )
  end

  # Without a current price there's nothing to compare with; the move is allowed.
  defp check_not_marketable(order, current_price) do
    with {:ok, current_cents} <- to_cents(current_price),
         {:fill, _} <- fill_rule(order, current_cents) do
      {:error, :would_fill_now}
    else
      _ -> :ok
    end
  end

  defp entry_side(:long), do: "buy"
  defp entry_side(:short), do: "short"

  defp exit_side("buy"), do: "sell"
  defp exit_side("short"), do: "cover"

  defp normalize_direction(direction) when direction in [:long, "long"], do: {:ok, :long}
  defp normalize_direction(direction) when direction in [:short, "short"], do: {:ok, :short}
  defp normalize_direction(_), do: {:error, :invalid_direction}

  defp verb("buy"), do: "Bought"
  defp verb("sell"), do: "Sold"
  defp verb("short"), do: "Shorted"
  defp verb("cover"), do: "Covered"

  # Conditional too: if it was cancelled meanwhile, it stays cancelled.
  defp reject(id, reason) do
    from(p in PendingOrder, where: p.id == ^id and p.status == "open")
    |> Repo.update_all(
      set: [status: "rejected", reject_reason: Atom.to_string(reason), updated_at: utc_now()]
    )
  end

  # An optional exit price, which must be on the right side of the limit. The stop is on the
  # losing side (below a long's entry, above a short's), the take-profit on the winning side.
  defp exit_cents(blank, _limit, _direction, _kind) when blank in [nil, ""], do: {:ok, nil}

  defp exit_cents(price, limit, direction, kind) do
    error = if kind == :stop, do: :invalid_stop, else: :invalid_take_profit

    with {:ok, cents} <- input_cents(price, error),
         true <- right_side?(cents, limit, direction, kind) do
      {:ok, cents}
    else
      _ -> {:error, error}
    end
  end

  defp right_side?(cents, limit, :long, :stop), do: cents < limit
  defp right_side?(cents, limit, :long, :take_profit), do: cents > limit
  defp right_side?(cents, limit, :short, :stop), do: cents > limit
  defp right_side?(cents, limit, :short, :take_profit), do: cents < limit

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

  defp fill("short", portfolio_id, ticker, quantity, price_cents),
    do: short(portfolio_id, ticker, quantity, price_cents, quantity * price_cents)

  defp fill("cover", portfolio_id, ticker, quantity, price_cents),
    do: cover(portfolio_id, ticker, quantity, price_cents, quantity * price_cents)

  defp buy(portfolio_id, ticker, quantity, price_cents, total_cents) do
    # Check-and-debit in one statement. Doing the write first also takes SQLite's write lock
    # at the start of the transaction, so the reads below can't go stale.
    debit!(portfolio_id, total_cents)

    case Repo.get_by(Position, portfolio_id: portfolio_id, ticker: ticker) do
      # Buying on a short would mean "cover", but Buy is the benchmark action and keeps one
      # meaning. The rollback also undoes the debit above.
      %Position{quantity: held} when held < 0 ->
        Repo.rollback(:short_open)

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

  # Short: sell shares you don't own, to buy them back lower. The position's quantity goes
  # negative and avg_cost_cents is the average *entry* price, so the P/L formula both UIs use,
  # (price - avg) * quantity, is right without a special case: with -10 shares, a drop is a
  # gain.
  #
  # Cash-secured: the full value is set aside from cash (same check-and-debit as a buy), so a
  # short uses buying power like a long does and the simulator never lends money. Real brokers
  # credit the proceeds and require margin; this is simpler and can't go bankrupt on paper.
  defp short(portfolio_id, ticker, quantity, price_cents, total_cents) do
    debit!(portfolio_id, total_cents)

    case Repo.get_by(Position, portfolio_id: portfolio_id, ticker: ticker) do
      nil ->
        Repo.insert!(%Position{
          portfolio_id: portfolio_id,
          ticker: ticker,
          quantity: -quantity,
          avg_cost_cents: price_cents
        })

      %Position{quantity: held} when held > 0 ->
        Repo.rollback(:long_open)

      position ->
        shorted = -position.quantity + quantity
        entry_cents = -position.quantity * position.avg_cost_cents + total_cents

        position
        |> Ecto.Changeset.change(
          quantity: -shorted,
          avg_cost_cents: div(entry_cents + div(shorted, 2), shorted)
        )
        |> Repo.update!()
    end

    insert_order(portfolio_id, "short", ticker, quantity, price_cents, total_cents)
  end

  # Cover: buy back shorted shares. Returns the collateral set aside at entry plus the P/L:
  #   quantity * avg (collateral) + quantity * (avg - price) (P/L) = quantity * (2 * avg - price)
  # If the price more than doubled, that's negative and the extra comes out of cash, which must
  # cover it (the conditional UPDATE checks, like a buy).
  defp cover(portfolio_id, ticker, quantity, price_cents, total_cents) do
    {reduced, _} =
      from(p in Position,
        where:
          p.portfolio_id == ^portfolio_id and p.ticker == ^ticker and p.quantity <= ^(-quantity)
      )
      |> Repo.update_all(inc: [quantity: quantity])

    if reduced == 0, do: Repo.rollback(:insufficient_short)

    position = Repo.get_by!(Position, portfolio_id: portfolio_id, ticker: ticker)
    credit_cents = quantity * (2 * position.avg_cost_cents - price_cents)

    {credited, _} =
      from(p in Portfolio, where: p.id == ^portfolio_id and p.cash_cents >= ^(-credit_cents))
      |> Repo.update_all(inc: [cash_cents: credit_cents])

    if credited == 0, do: Repo.rollback(:insufficient_cash)

    if position.quantity == 0, do: Repo.delete!(position)

    insert_order(portfolio_id, "cover", ticker, quantity, price_cents, total_cents)
  end

  # Check-and-debit in one statement (see buy/5). Rolls back the transaction when it fails.
  defp debit!(portfolio_id, total_cents) do
    {debited, _} =
      from(p in Portfolio, where: p.id == ^portfolio_id and p.cash_cents >= ^total_cents)
      |> Repo.update_all(inc: [cash_cents: -total_cents])

    if debited == 0 do
      Repo.rollback(
        if Repo.get(Portfolio, portfolio_id), do: :insufficient_cash, else: :portfolio_not_found
      )
    end
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
  defp normalize_side(side) when side in ["short", :short], do: {:ok, "short"}
  defp normalize_side(side) when side in ["cover", :cover], do: {:ok, "cover"}
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
