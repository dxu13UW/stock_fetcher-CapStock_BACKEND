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
  pubsub_server: StockFetcher.PubSub,
  live_view: [signing_salt: "KolMj9f6"]

# JS bundler: assets/js/app.js -> priv/static/assets/js/app.js.
# NODE_PATH lets `import "phoenix_live_view"` resolve to the Hex package's JS in deps/.
config :esbuild,
  version: "0.25.0",
  stock_fetcher: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Tailwind v4: no tailwind.config.js; configuration lives in assets/css/app.css.
config :tailwind,
  version: "4.3.0",
  stock_fetcher: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

import_config "#{config_env()}.exs"
