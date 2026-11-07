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
        {Phoenix.PubSub, name: StockFetcher.PubSub},
        {StockFetcher.Mock.Streamer,
         [enabled: Application.get_env(:stock_fetcher, :enable_mock_stream, true)]}
      ] ++
        order_watchers() ++
        [
          StockFetcherWeb.Endpoint
          # Append processes here.
        ]

    opts = [strategy: :one_for_one, name: StockFetcher.Supervisor]
    Supervisor.start_link(children, opts)
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
