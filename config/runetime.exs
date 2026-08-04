import Config

if config_env() == :prod do
  cors_origins =
    System.get_env("CORS_ALLOWED_ORIGINS", "")
    |> String.split(",", trim: true)

  config :stock_fetcher, :cors_origins, cors_origins
end
