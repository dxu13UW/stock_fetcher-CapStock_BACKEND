defmodule StockFetcher.Trading.Order do
  @moduledoc "One filled order. Market orders fill immediately, so every row is a fill."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "orders" do
    field(:ticker, :string)
    field(:side, :string)
    field(:quantity, :integer)
    field(:price_cents, :integer)
    field(:total_cents, :integer)
    # nil = manual market order; "limit_entry" | "take_profit" | "stop_loss" = a resting order
    # filled (set by Trading.fill_pending_order/2).
    field(:via, :string)

    belongs_to(:portfolio, StockFetcher.Trading.Portfolio)

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
