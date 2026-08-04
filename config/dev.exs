import Config

config :stock_fetcher, :cors_origins, [
  "http://localhost:5173",
  "http://localhost:3000",
  "http://localhost:8080"
]

config :stock_fetcher, StockFetcher.Repo,
  database: Path.expand("../stock_fetcher_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  busy_timeout: 5000,
  wal_trigger: 1000,
  journal_mode: :wal

config :stock_fetcher, StockFetcherWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  server: true,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "a_long_random_development_secret_key_base_here_at_least_64_bytes"

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :plug_init_mode, :runtime
