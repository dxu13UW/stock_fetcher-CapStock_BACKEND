defmodule StockFetcher.StockPrice do
  @moduledoc """
  Defines the Ecto database schema and changeset validation rules for individual stock price records.
  It maps database table fields—such as ticker symbols, float prices, and automatic timestamps—and provides
  the `changeset/2` function to ensure required data attributes are present before insertion.
  """
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
    |> validate_number(:price, greater_than: 0)
  end
end
