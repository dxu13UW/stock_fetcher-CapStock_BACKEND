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
    # How it was placed: "manual" (a Buy/Sell/Short/Cover click, the default) or, when a resting
    # order filled, "limit_entry" | "take_profit" | "stop_loss" (set by
    # Trading.fill_pending_order/2). Older rows have nil, shown as manual.
    field(:via, :string, default: "manual")

    belongs_to(:portfolio, StockFetcher.Trading.Portfolio)

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
