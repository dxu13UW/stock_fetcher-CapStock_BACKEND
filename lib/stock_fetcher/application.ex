defmodule StockFetcher.Application do
  use Application

  @impl true
  def start(_type, _args) do
    StockFetcherWeb.TelemetryHandler.attach()

    children = [
      StockFetcher.Repo,
      {StockFetcher.Worker, []},
      StockFetcher.Pruner,
      {Phoenix.PubSub, name: StockFetcher.PubSub},
      {StockFetcher.Mock.Streamer,
       [enabled: Application.get_env(:stock_fetcher, :enable_mock_stream, true)]},
      StockFetcherWeb.Endpoint
      # Append processes here.
    ]

    opts = [strategy: :one_for_one, name: StockFetcher.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
