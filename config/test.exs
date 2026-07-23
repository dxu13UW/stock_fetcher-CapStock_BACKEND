# Ensures ExUnit runs on SQLite sandbox.
import Config

# Override Repo settings for ExUnit test runs, deploy a sandbox database
config :stock_fetcher, StockFetcher.Repo,
  database: "/app/db/stock_fetcher_test.db",
  pool: Ecto.Adapters.SQL.Sandbox

# Attach Req.Test plug and disable retries during test execution
config :stock_fetcher, :req_options,
  plug: {Req.Test, StockFetcher},
  retry: false
