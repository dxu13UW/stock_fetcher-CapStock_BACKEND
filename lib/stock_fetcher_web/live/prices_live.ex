defmodule StockFetcherWeb.PricesLive do
  @moduledoc """
  Read-only live prices page (PLAN.md step B), at /prices.

  One of these processes runs per open browser tab. It holds the page state in
  `socket.assigns`; whenever assigns change, LiveView re-runs `render/1` and sends
  only the changed parts of the HTML to the browser.
  """
  use StockFetcherWeb, :live_view

  # TODO(1) mount/3 runs TWICE: once for the plain HTTP request (so the first paint is
  #   real HTML, good for SEO and slow networks) and again when the browser's WebSocket
  #   connects. Subscribe to "stocks:live" only on the second run:
  #
  #     if connected?(socket), do: Phoenix.PubSub.subscribe(StockFetcher.PubSub, "stocks:live")
  #
  #   Question to answer in LOG.md: why would subscribing on the first (HTTP) run be
  #   wrong? Hint: which process is running mount/3 at that point, and how long does it live?
  #
  # TODO(2) Load starting prices so the page isn't empty until the next 15s tick.
  #   StockFetcher.get_hydrated_watchlist/0 returns %{"AAPL" => [%StockPrice{}, ...]}
  #   (oldest first), but it loads 12h of rows per ticker just to show one price. Decide:
  #   use it, or add a small `latest_prices/0` query to StockFetcher (and test it).
  #   Keep CLAUDE.md's rule: no Finnhub/Alpaca calls from a LiveView.
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(StockFetcher.PubSub, "stocks:live")

    {:ok, assign(socket, prices: %{})}
  end

  # TODO(3) Handle the broadcast. TelemetryHandler sends
  #   {"new_price", %{id: _, ticker: "AAPL", price: 189.5, timestamp: ~N[...]}}
  #   to every subscriber. Add:
  #
  #     @impl true
  #     def handle_info({"new_price", payload}, socket) do
  #       ...update the :prices assign (see `update/3`)...
  #       {:noreply, socket}
  #     end
  #
  #   Note: `price` arrives as a float (TelemetryHandler converts it). Fine for display;
  #   the trading module must use Decimal from the DB instead (CLAUDE.md money rule).

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-2xl p-6">
      <h1 class="text-2xl font-semibold">Live Prices</h1>

      <p :if={@prices == %{}} class="mt-4 text-zinc-500">Waiting for prices…</p>

      <%!-- TODO(4) Render a table: one row per ticker in @prices (ticker, price, time).
            HEEx basics: {expr} interpolates; :for={x <- list} repeats a tag;
            :if={cond} shows it conditionally. Sort the tickers so rows don't jump. --%>
    </main>
    """
  end
end
