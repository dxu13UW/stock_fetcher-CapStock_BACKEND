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

# Trading rejects live orders outside market hours. Pin the clock to a Wednesday, 11:00 AM ET,
# so order tests pass whenever they run; tests for the closed market pass `now:` or override it.
config :stock_fetcher, :trading_fixed_now, ~U[2026-11-04 16:00:00Z]

# OrderWatchers query the DB on every tick; the global ones would run outside the SQL sandbox.
# Tests that need one start it themselves.
config :stock_fetcher, :enable_order_watchers, false
config :stock_fetcher, :enable_alpaca_poller, false
config :stock_fetcher, :enable_session_janitor, false
config :stock_fetcher, :enable_candle_bars, false
