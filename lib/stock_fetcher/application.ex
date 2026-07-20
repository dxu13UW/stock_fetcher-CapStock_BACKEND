defmodule StockFetcher.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StockFetcher.Repo,
      # 💡 Add your background worker here so it starts automatically!
      {StockFetcher.Worker, []}
    ]

    opts = [strategy: :one_for_one, name: StockFetcher.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
