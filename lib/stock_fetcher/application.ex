defmodule StockFetcher.Application do
  use Application

  @impl true
  def start(_type, _args) do
    StockFetcherWeb.TelemetryHandler.attach()

    children =
      [
        StockFetcher.Repo,
        {StockFetcher.Worker, []},
        StockFetcher.Pruner,
        {Phoenix.PubSub, name: StockFetcher.PubSub}
      ] ++
        session_janitor() ++
        [
          {StockFetcher.Mock.Streamer,
           [enabled: Application.get_env(:stock_fetcher, :enable_mock_stream, true)]},
          # The other 45 mock tickers (2026-11-07), on their own topic so React keeps its 5.
          Supervisor.child_spec(
            {StockFetcher.Mock.Streamer,
             [
               name: StockFetcher.Mock.Streamer.Extra,
               topic: "stocks:mock:extra",
               prices: StockFetcher.Tickers.mock_prices(:extra),
               per_tick: 6,
               enabled: Application.get_env(:stock_fetcher, :enable_mock_stream, true)
             ]},
            id: :mock_streamer_extra
          )
        ] ++
        alpaca_poller() ++
        [
          # Chart history per source (2026-11-07). After PubSub and the streams it folds in.
          {StockFetcher.Candles,
           source: :live,
           fetch_bars: Application.get_env(:stock_fetcher, :enable_candle_bars, true)},
          {StockFetcher.Candles, source: :mock}
        ] ++
        order_watchers() ++
        [
          StockFetcherWeb.Endpoint
          # Append processes here.
        ]

    opts = [strategy: :one_for_one, name: StockFetcher.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Deletes a tab's private portfolio when the tab closes; off in tests (SQL sandbox).
  defp session_janitor do
    if Application.get_env(:stock_fetcher, :enable_session_janitor, true),
      do: [StockFetcher.Trading.SessionJanitor],
      else: []
  end

  # Live prices for the 45 extra tickers. Needs the Alpaca keys; off in tests (they start
  # their own with a stubbed HTTP client). After PubSub, which it broadcasts on.
  defp alpaca_poller do
    if Application.get_env(:stock_fetcher, :enable_alpaca_poller, true) and
         StockFetcher.Alpaca.Poller.configured?() do
      [StockFetcher.Alpaca.Poller]
    else
      []
    end
  end

  # Fill resting orders (step G), one per price stream; after PubSub, which they subscribe to.
  # Off in tests (config/test.exs): tests start their own against the SQL sandbox.
  defp order_watchers do
    if Application.get_env(:stock_fetcher, :enable_order_watchers, true) do
      [{StockFetcher.OrderWatcher, source: :live}, {StockFetcher.OrderWatcher, source: :mock}]
    else
      []
    end
  end
end
