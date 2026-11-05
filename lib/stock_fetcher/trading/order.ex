defmodule StockFetcher.Trading.Order do
  @moduledoc "One filled order. Market orders fill immediately, so every row is a fill."
  use Ecto.Schema

  schema "orders" do
    field(:ticker, :string)
    field(:side, :string)
    field(:quantity, :integer)
    field(:price_cents, :integer)
    field(:total_cents, :integer)

    belongs_to(:portfolio, StockFetcher.Trading.Portfolio)

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
