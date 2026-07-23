# Base configuration module for the StockFetcher application across all execution environments.
import Config

# 1. Register Ecto Repositories for Mix tasks (e.g., mix ecto.migrate)
config :stock_fetcher,
  ecto_repos: [StockFetcher.Repo]

# 2. Configure the SQLite Database Repository
config :stock_fetcher, StockFetcher.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "/app/db/stock_fetcher.db",
  pool_size: 5

# 3. Import environment-specific configs (dev.exs, test.exs, prod.exs) if they exist
target_file = Path.join(__DIR__, "#{config_env()}.exs")

if File.exists?(target_file) do
  import_config target_file
end
