import Config

# Override Repo settings for ExUnit test runs, deploy a sandbox database
config :stock_fetcher, StockFetcher.Repo,
  database: Path.expand("../sqlite_data/stock_fetcher_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox

config :stock_fetcher, StockFetcherWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: "a_long_random_development_secret_key_base_here_at_least_64_bytes",
  debug_errors: true

# Attach Req.Test plug and disable retries during test execution
config :stock_fetcher, :req_options,
  plug: {Req.Test, StockFetcher},
  retry: false
