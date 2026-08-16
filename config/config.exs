# Base configuration module for the StockFetcher application across all execution environments.
import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :stock_fetcher,
  ecto_repos: [StockFetcher.Repo]

config :stock_fetcher, StockFetcher.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "/app/db/stock_fetcher.db",
  pool_size: 5

config :stock_fetcher, StockFetcherWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: StockFetcherWeb.ErrorJSON],
    accepts: ~w(json)
  ],
  pubsub_server: StockFetcher.PubSub

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

import_config "#{config_env()}.exs"
