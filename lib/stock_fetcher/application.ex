defmodule StockFetcher.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StockFetcher.Repo,
      {StockFetcher.Worker, []}
      # Append workers here.
    ]

    opts = [strategy: :one_for_one, name: StockFetcher.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
