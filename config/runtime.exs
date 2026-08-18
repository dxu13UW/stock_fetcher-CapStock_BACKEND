import Config

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /app/db/stock_fetcher_prod.db
      """

  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :stock_fetcher, StockFetcher.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  config :stock_fetcher, StockFetcherWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0},
      port: port,
      thousand_island_options: [
        num_connections: 128,
        num_acceptors: 4
      ]
    ],
    secret_key_base: secret_key_base,
    check_origin: [
      "//localhost",
      "//localhost:5173",
      "//localhost:3000",
      "//#{host}",
      "https://tinle-ri.github.io"
    ]
end
