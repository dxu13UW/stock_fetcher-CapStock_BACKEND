defmodule StockFetcher.Repo do
  use Ecto.Repo,
    otp_app: :stock_fetcher,
    adapter: Ecto.Adapters.SQLite3
end
