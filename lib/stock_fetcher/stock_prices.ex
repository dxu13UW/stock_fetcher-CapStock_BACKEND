defmodule StockFetcher.StockPrice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stock_prices" do
    field(:ticker, :string)
    field(:price, :float)

    timestamps()
  end

  def changeset(stock_price, attrs) do
    stock_price
    |> cast(attrs, [:ticker, :price])
    |> validate_required([:ticker, :price])
  end
end
