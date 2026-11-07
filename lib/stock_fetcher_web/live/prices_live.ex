defmodule StockFetcherWeb.PricesLive do
  @moduledoc """
  Live prices (PLAN.md step B) and the LiveView trading panel (step E), at /prices.

  One of these processes runs per open browser tab. It holds the page state in
  `socket.assigns`; whenever assigns change, LiveView re-runs `render/1` and sends
  only the changed parts of the HTML to the browser.

  `@prices` is `%{ticker => %{ticker, price, timestamp}}`, the broadcast payload shape,
  whether an entry came from the DB (mount) or from a broadcast (handle_info).

  Trading panel (benchmark spec, PLAN.md section 4): market orders on the shared demo portfolio,
  filled at the price in `@prices`, the same number the page shows (LOG.md, step D).
  """
  use StockFetcherWeb, :live_view

  alias StockFetcher.Trading

  # mount/3 runs twice: once in a one-shot process for the plain HTTP render, then again in
  # the long-lived LiveView process when the WebSocket connects (see LOG.md, TODO 1).
  # Subscribe only when connected; load prices on both runs so the first HTML has data.
  #
  # Two sources, like the React app's two channel topics:
  #   /prices              -> "stocks:live" (real Finnhub ticks, saved to the DB; market hours)
  #   /prices?source=mock  -> "stocks:mock" (Mock.Streamer, every 1.5 s, never saved)
  @impl true
  def mount(params, _session, socket) do
    source = if params["source"] == "mock", do: :mock, else: :live

    # Mock trades go to their own portfolio, so made-up prices never touch real positions.
    portfolio = Trading.demo_portfolio(source)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(StockFetcher.PubSub, topic(source))
      # OrderWatcher reports resting-order fills here, even ones placed from another tab.
      Phoenix.PubSub.subscribe(StockFetcher.PubSub, Trading.portfolio_topic(portfolio.id))
    end

    prices = initial_prices(source)

    {:ok,
     assign(socket,
       source: source,
       prices: prices,
       # Its own assign, so a price tick doesn't re-send the dropdown options (only a new ticker
       # does). Re-rendering a <select> closes it and resets the choice.
       tickers: prices |> Map.keys() |> Enum.sort(),
       # What the user has typed/selected, kept on the server via phx-change. LiveView only
       # protects the focused input from re-renders; without this, every tick would reset the
       # other fields to the rendered defaults.
       order_form: %{"ticker" => nil, "quantity" => "1"},
       limit_form: %{"ticker" => nil, "quantity" => "1", "limit" => "", "stop" => ""},
       portfolio: portfolio,
       orders: Trading.list_orders(portfolio.id),
       pending: Trading.list_pending_orders(portfolio.id),
       # nil, or {:ok, text} / {:error, text} from the last order
       message: nil
     )}
  end

  defp topic(:live), do: "stocks:live"
  defp topic(:mock), do: "stocks:mock"

  defp initial_prices(:live) do
    Map.new(StockFetcher.latest_prices(), fn row ->
      {row.ticker, %{ticker: row.ticker, price: row.price, timestamp: row.inserted_at}}
    end)
  end

  # Mock prices only exist in Mock.Streamer's state; the first tick arrives within 1.5 s.
  defp initial_prices(:mock), do: %{}

  # Every price broadcast on the subscribed topic (TelemetryHandler or Mock.Streamer) lands
  # here. Map.take drops the payload's `id`, so entries match the mount shape exactly.
  # Any other message on the price topic would crash this process, which is the right signal
  # that the payload contract changed.
  @impl true
  def handle_info({"new_price", payload}, socket) do
    price = Map.take(payload, [:ticker, :price, :timestamp])
    socket = update(socket, :prices, &Map.put(&1, price.ticker, price))

    socket =
      if price.ticker in socket.assigns.tickers,
        do: socket,
        else: update(socket, :tickers, &Enum.sort([price.ticker | &1]))

    {:noreply, socket}
  end

  # From OrderWatcher: a resting order filled or was rejected. The DB already changed, so reload.
  def handle_info({:pending_order_event, kind, text}, socket) do
    {:noreply, socket |> reload_trading() |> assign(message: {kind, text})}
  end

  # The form's Buy/Sell button that was clicked arrives as "side" (the submitter's name/value).
  @impl true
  def handle_event("order", %{"ticker" => ticker, "quantity" => quantity, "side" => side}, socket) do
    # Step D: the price is the one this page is showing; nil if the ticker has none.
    price = get_in(socket.assigns.prices, [ticker, :price])

    result =
      Trading.place_market_order(socket.assigns.portfolio.id, side, ticker, quantity, price,
        source: socket.assigns.source
      )

    case result do
      {:ok, %{order: order, portfolio: portfolio}} ->
        {:noreply,
         assign(socket,
           portfolio: portfolio,
           orders: Trading.list_orders(portfolio.id),
           message: {:ok, confirmation(order)}
         )}

      {:error, reason} ->
        {:noreply, assign(socket, message: {:error, Trading.error_message(reason)})}
    end
  end

  # phx-change: remember the form's current values so re-renders keep them.
  def handle_event("order_form", params, socket),
    do: {:noreply, assign(socket, order_form: Map.take(params, ["ticker", "quantity"]))}

  def handle_event("limit_form", params, socket) do
    {:noreply,
     assign(socket, limit_form: Map.take(params, ["ticker", "quantity", "limit", "stop"]))}
  end

  # Limit buy entry with an optional stop-loss (step G, LiveView only).
  def handle_event("limit_order", params, socket) do
    %{"ticker" => ticker, "quantity" => quantity, "limit" => limit} = params
    portfolio_id = socket.assigns.portfolio.id

    result =
      Trading.place_limit_order(portfolio_id, ticker, quantity, limit, params["stop"],
        source: socket.assigns.source,
        current_price: get_in(socket.assigns.prices, [ticker, :price])
      )

    message =
      case result do
        {:ok, :placed, pending} -> {:ok, "Placed #{Trading.describe(pending)}."}
        {:ok, :filled, %{order: order}} -> {:ok, "Filled now: " <> confirmation(order)}
        {:error, reason} -> {:error, Trading.error_message(reason)}
      end

    {:noreply, socket |> reload_trading() |> assign(message: message)}
  end

  def handle_event("cancel_order", %{"id" => id}, socket) do
    message =
      case Trading.cancel_pending_order(socket.assigns.portfolio.id, id) do
        {:ok, pending} -> {:ok, "Cancelled #{Trading.describe(pending)}."}
        {:error, reason} -> {:error, Trading.error_message(reason)}
      end

    {:noreply, socket |> reload_trading() |> assign(message: message)}
  end

  defp reload_trading(socket) do
    id = socket.assigns.portfolio.id

    assign(socket,
      portfolio: Trading.get_portfolio!(id),
      orders: Trading.list_orders(id),
      pending: Trading.list_pending_orders(id)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-2xl p-6">
      <h1 class="text-2xl font-semibold">Live Prices</h1>
      <p class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
        Source: {if @source == :mock, do: "mock stream (simulated)", else: "live market data"}
      </p>

      <p :if={@prices == %{}} class="mt-4 text-zinc-500 dark:text-zinc-400">Waiting for prices…</p>

      <table :if={@prices != %{}} id="prices" class="mt-6 w-full text-left">
        <thead class="border-b border-zinc-300 text-sm text-zinc-500 dark:border-zinc-700 dark:text-zinc-400">
          <tr>
            <th class="py-2">Ticker</th>
            <th class="py-2 text-right">Price</th>
            <th class="py-2 text-right">Updated (UTC)</th>
          </tr>
        </thead>
        <tbody>
          <%!-- Sorted by ticker so rows never jump; the id lets LiveView patch one row in place. --%>
          <tr
            :for={p <- Enum.sort_by(Map.values(@prices), & &1.ticker)}
            id={"price-#{p.ticker}"}
            class="border-b border-zinc-100 dark:border-zinc-800"
          >
            <td class="py-2 font-medium">{p.ticker}</td>
            <td class="py-2 text-right tabular-nums">${format_price(p.price)}</td>
            <td class="py-2 text-right tabular-nums text-zinc-500 dark:text-zinc-400">{format_time(p.timestamp)}</td>
          </tr>
        </tbody>
      </table>

      <section id="trade" class="mt-10">
        <h2 class="text-xl font-semibold">Trade</h2>
        <p class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
          Paper trading: market orders fill at the price shown above.
        </p>

        <form id="order-form" phx-submit="order" phx-change="order_form" class="mt-4 flex flex-wrap items-end gap-3">
          <label class="flex flex-col text-sm">
            Ticker
            <select name="ticker" class="mt-1 rounded border border-zinc-300 bg-white px-2 py-1 dark:border-zinc-700 dark:bg-zinc-900">
              <option :for={ticker <- @tickers} value={ticker} selected={ticker == @order_form["ticker"]}>
                {ticker}
              </option>
            </select>
          </label>
          <label class="flex flex-col text-sm">
            Quantity
            <input
              type="number"
              name="quantity"
              value={@order_form["quantity"]}
              phx-debounce="250"
              min="1"
              step="1"
              class="mt-1 w-28 rounded border border-zinc-300 bg-white px-2 py-1 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>
          <button
            type="submit"
            name="side"
            value="buy"
            disabled={@tickers == []}
            class="rounded bg-emerald-600 px-4 py-1.5 font-medium text-white disabled:opacity-40"
          >
            Buy
          </button>
          <button
            type="submit"
            name="side"
            value="sell"
            disabled={@tickers == []}
            class="rounded bg-rose-600 px-4 py-1.5 font-medium text-white disabled:opacity-40"
          >
            Sell
          </button>
        </form>

        <p
          :if={@message}
          id="order-message"
          class={[
            "mt-3 text-sm font-medium",
            if(elem(@message, 0) == :ok, do: "text-emerald-700 dark:text-emerald-400", else: "text-rose-700 dark:text-rose-400")
          ]}
        >
          {elem(@message, 1)}
        </p>

        <form id="limit-form" phx-submit="limit_order" phx-change="limit_form" class="mt-6 flex flex-wrap items-end gap-3">
          <span class="w-full text-sm font-semibold">Limit buy with stop-loss</span>
          <label class="flex flex-col text-sm">
            Ticker
            <select name="ticker" class="mt-1 rounded border border-zinc-300 bg-white px-2 py-1 dark:border-zinc-700 dark:bg-zinc-900">
              <option :for={ticker <- @tickers} value={ticker} selected={ticker == @limit_form["ticker"]}>
                {ticker}
              </option>
            </select>
          </label>
          <label class="flex flex-col text-sm">
            Quantity
            <input
              type="number"
              name="quantity"
              value={@limit_form["quantity"]}
              phx-debounce="250"
              min="1"
              step="1"
              class="mt-1 w-24 rounded border border-zinc-300 bg-white px-2 py-1 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>
          <label class="flex flex-col text-sm">
            Limit $
            <input
              type="number"
              name="limit"
              value={@limit_form["limit"]}
              phx-debounce="250"
              min="0.01"
              step="0.01"
              required
              class="mt-1 w-28 rounded border border-zinc-300 bg-white px-2 py-1 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>
          <label class="flex flex-col text-sm">
            Stop $ (optional)
            <input
              type="number"
              name="stop"
              value={@limit_form["stop"]}
              phx-debounce="250"
              min="0.01"
              step="0.01"
              class="mt-1 w-28 rounded border border-zinc-300 bg-white px-2 py-1 dark:border-zinc-700 dark:bg-zinc-900"
            />
          </label>
          <button
            type="submit"
            disabled={@tickers == []}
            class="rounded bg-sky-600 px-4 py-1.5 font-medium text-white disabled:opacity-40"
          >
            Place limit buy
          </button>
          <span class="w-full text-xs text-zinc-500 dark:text-zinc-400">
            Fills only when the price trades below the limit, at the limit price. The stop-loss
            then sells at the first price at or below the stop, which can be lower if the price gaps.
          </span>
        </form>

        <p id="cash" class="mt-6 text-lg">
          Cash: <span class="font-semibold tabular-nums">{format_cents(@portfolio.cash_cents)}</span>
        </p>

        <h3 class="mt-6 font-semibold">Positions</h3>
        <p :if={@portfolio.positions == []} class="mt-2 text-sm text-zinc-500 dark:text-zinc-400">No positions.</p>
        <table :if={@portfolio.positions != []} id="positions" class="mt-2 w-full text-left">
          <thead class="border-b border-zinc-300 text-sm text-zinc-500 dark:border-zinc-700 dark:text-zinc-400">
            <tr>
              <th class="py-2">Ticker</th>
              <th class="py-2 text-right">Qty</th>
              <th class="py-2 text-right">Avg cost</th>
              <th class="py-2 text-right">Price</th>
              <th class="py-2 text-right">P/L</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={pos <- @portfolio.positions}
              id={"position-#{pos.ticker}"}
              class="border-b border-zinc-100 dark:border-zinc-800"
            >
              <td class="py-2 font-medium">{pos.ticker}</td>
              <td class="py-2 text-right tabular-nums">{pos.quantity}</td>
              <td class="py-2 text-right tabular-nums">{format_cents(pos.avg_cost_cents)}</td>
              <td class="py-2 text-right tabular-nums">{position_price(@prices, pos)}</td>
              <td class="py-2 text-right tabular-nums">{position_pnl(@prices, pos)}</td>
            </tr>
          </tbody>
        </table>

        <h3 class="mt-6 font-semibold">Open orders</h3>
        <p :if={@pending == []} class="mt-2 text-sm text-zinc-500 dark:text-zinc-400">No open orders.</p>
        <ul :if={@pending != []} id="open-orders" class="mt-2 space-y-1 text-sm tabular-nums">
          <li :for={p <- @pending} id={"pending-#{p.id}"} class="flex items-center gap-3">
            <span>{Trading.describe(p)}</span>
            <button
              type="button"
              phx-click="cancel_order"
              phx-value-id={p.id}
              class="rounded border border-zinc-300 px-2 py-0.5 text-xs dark:border-zinc-700"
            >
              Cancel
            </button>
          </li>
        </ul>

        <h3 class="mt-6 font-semibold">Order history</h3>
        <p :if={@orders == []} class="mt-2 text-sm text-zinc-500 dark:text-zinc-400">No orders yet.</p>
        <ul :if={@orders != []} id="orders" class="mt-2 space-y-1 text-sm tabular-nums">
          <li :for={order <- @orders} id={"order-#{order.id}"}>
            {format_time(order.inserted_at)} {String.upcase(order.side)} {order.quantity} {order.ticker}
            @ {format_cents(order.price_cents)} ({format_cents(order.total_cents)})
          </li>
        </ul>
      </section>
    </main>
    """
  end

  # Confirmation text for a filled order, e.g. "Bought 10 AAPL at $189.57 ($1,895.70)".
  # Shared with the React API so both panels show the same text.
  defp confirmation(order), do: Trading.confirmation(order)

  # Current price and unrealized P/L for a position, from the live prices on this page.
  # "–" when the ticker has no price yet (e.g. the mock stream just started).
  defp position_price(prices, pos) do
    case current_cents(prices, pos.ticker) do
      nil -> "–"
      cents -> format_cents(cents)
    end
  end

  defp position_pnl(prices, pos) do
    case current_cents(prices, pos.ticker) do
      nil -> "–"
      cents -> format_signed_cents((cents - pos.avg_cost_cents) * pos.quantity)
    end
  end

  # Display only: the trading module does its own exact conversion when an order fills.
  defp current_cents(prices, ticker) do
    case prices[ticker] do
      %{price: price} -> round(price * 100)
      nil -> nil
    end
  end

  # Integer cents -> "$1,234.56" (or "-$1,234.56").
  defp format_cents(cents), do: Trading.format_cents(cents)

  defp format_signed_cents(cents) when cents > 0, do: "+" <> format_cents(cents)
  defp format_signed_cents(cents), do: format_cents(cents)

  # Display only. Prices are floats here; the trading module converts to integer cents.
  defp format_price(price) when is_number(price),
    do: :erlang.float_to_binary(price / 1, decimals: 2)

  # Works for DateTime (DB rows, Mock.Streamer) and NaiveDateTime.
  defp format_time(%{} = timestamp), do: Calendar.strftime(timestamp, "%H:%M:%S")
end
