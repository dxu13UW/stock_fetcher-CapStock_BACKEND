defmodule StockFetcherWeb.PricesLive do
  @moduledoc """
  Read-only live prices page (PLAN.md step B), at /prices.

  One of these processes runs per open browser tab. It holds the page state in
  `socket.assigns`; whenever assigns change, LiveView re-runs `render/1` and sends
  only the changed parts of the HTML to the browser.

  `@prices` is `%{ticker => %{ticker, price, timestamp}}`, the broadcast payload shape,
  whether an entry came from the DB (mount) or from a broadcast (handle_info).
  """
  use StockFetcherWeb, :live_view

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

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(StockFetcher.PubSub, topic(source))

    {:ok, assign(socket, source: source, prices: initial_prices(source))}
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
  # "new_price" is the only message on this topic; anything else would crash this process,
  # which is the right signal that the payload contract changed.
  @impl true
  def handle_info({"new_price", payload}, socket) do
    price = Map.take(payload, [:ticker, :price, :timestamp])

    {:noreply, update(socket, :prices, &Map.put(&1, price.ticker, price))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-2xl p-6">
      <h1 class="text-2xl font-semibold">Live Prices</h1>
      <p class="mt-1 text-sm text-zinc-500">
        Source: {if @source == :mock, do: "mock stream (simulated)", else: "live market data"}
      </p>

      <p :if={@prices == %{}} class="mt-4 text-zinc-500">Waiting for prices…</p>

      <table :if={@prices != %{}} id="prices" class="mt-6 w-full text-left">
        <thead class="border-b border-zinc-300 text-sm text-zinc-500">
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
            class="border-b border-zinc-100"
          >
            <td class="py-2 font-medium">{p.ticker}</td>
            <td class="py-2 text-right tabular-nums">${format_price(p.price)}</td>
            <td class="py-2 text-right tabular-nums text-zinc-500">{format_time(p.timestamp)}</td>
          </tr>
        </tbody>
      </table>
    </main>
    """
  end

  # Display only. Prices are floats here; the trading module converts to integer cents.
  defp format_price(price) when is_number(price),
    do: :erlang.float_to_binary(price / 1, decimals: 2)

  # Works for DateTime (DB rows, Mock.Streamer) and NaiveDateTime.
  defp format_time(%{} = timestamp), do: Calendar.strftime(timestamp, "%H:%M:%S")
end
