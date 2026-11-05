defmodule StockFetcher.Trading.Portfolio do
  @moduledoc "A paper-trading account: cash in integer cents plus its positions."
  use Ecto.Schema

  schema "portfolios" do
    field(:name, :string)
    field(:cash_cents, :integer)

    has_many(:positions, StockFetcher.Trading.Position, preload_order: [asc: :ticker])
    has_many(:orders, StockFetcher.Trading.Order)

    timestamps(type: :utc_datetime)
  end
end
