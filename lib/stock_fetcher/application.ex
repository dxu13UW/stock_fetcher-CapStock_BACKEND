defmodule StockFetcher.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StockFetcher.Repo,
      {StockFetcher.Worker, []},
      StockFetcher.Pruner
      # Append processes here.
    ]

    opts = [strategy: :one_for_one, name: StockFetcher.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
