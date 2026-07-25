# Base configuration module for the StockFetcher application across all execution environments.
import Config

config :stock_fetcher,
  ecto_repos: [StockFetcher.Repo]

config :stock_fetcher, StockFetcher.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "/app/db/stock_fetcher.db",
  pool_size: 5

config :stock_fetcher, StockFetcherWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: StockFetcherWeb.ErrorJSON], accept_s: ~w(json)],
  pubsub_server: StockFetcher.PubSub

target_file = Path.join(__DIR__, "#{config_env()}.exs")

if File.exists?(target_file) do
  import_config target_file
end
