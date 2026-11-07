defmodule StockFetcher.Trading.PendingOrder do
  @moduledoc """
  A resting order (step G): a limit buy entry, or the stop-loss sell it creates when it fills.
  Waits with status "open" until a price from its `source` stream triggers it.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "pending_orders" do
    field(:source, :string)
    field(:ticker, :string)
    field(:type, :string)
    field(:side, :string)
    field(:quantity, :integer)
    field(:trigger_cents, :integer)
    field(:stop_cents, :integer)
    field(:status, :string, default: "open")
    field(:reject_reason, :string)

    belongs_to(:portfolio, StockFetcher.Trading.Portfolio)
    belongs_to(:order, StockFetcher.Trading.Order)
    belongs_to(:parent, __MODULE__)

    timestamps(type: :utc_datetime)
  end
end
