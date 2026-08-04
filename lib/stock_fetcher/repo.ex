defmodule StockFetcher.Repo do
  @moduledoc """
  Wrapper module for Ecto repository functions configured specifically for an SQLite3 database adapter.
  It manages the application's underlying database connection pool and handles query execution for inserting,
  updating, and fetching `StockPrice` records.
  """
  use Ecto.Repo,
    otp_app: :stock_fetcher,
    adapter: Ecto.Adapters.SQLite3
end
