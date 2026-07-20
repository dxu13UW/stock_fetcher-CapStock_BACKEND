import Config

config :stock_fetcher, StockFetcher.Repo,
  database: "stock_fetcher_repo",
  username: "user",
  password: "pass",
  hostname: "localhost"

config :stock_fetcher, StockerFetcher.Repo,
  adapter: Ecto.Adapter.SQLite3,
  database: "/app/db/stock_fetcher.db",
  pool_size: 5

config :stock_fetcher, ecto_repos: [StockFetcher.Repo]
