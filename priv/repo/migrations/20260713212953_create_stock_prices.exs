defmodule StockFetcher.Repo.Migrations.CreateStockPrices do
  use Ecto.Migration

  def change do
    create table(:stock_prices) do
      add :ticker, :string
      add :price, :float

      timestamps(type: :utc_datetime)
    end
  end
end
