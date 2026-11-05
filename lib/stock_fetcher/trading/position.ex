defmodule StockFetcher.Trading.Position do
  @moduledoc "Shares of one ticker held by a portfolio, with the average cost per share in cents."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "positions" do
    field(:ticker, :string)
    field(:quantity, :integer)
    field(:avg_cost_cents, :integer)

    belongs_to(:portfolio, StockFetcher.Trading.Portfolio)

    timestamps(type: :utc_datetime)
  end
end
