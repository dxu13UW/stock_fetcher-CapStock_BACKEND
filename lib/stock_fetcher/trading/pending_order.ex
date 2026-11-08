defmodule StockFetcher.Trading.PendingOrder do
  @moduledoc """
  A resting order: a limit entry (long `side: "buy"` or short `side: "short"`), or one of the
  exits it creates when it fills: a stop-loss (`type: "stop"`) and/or a take-profit
  (`type: "limit"`), both with `parent_id` set to the entry. Exits close the position, so their
  side is `"sell"` for a long and `"cover"` for a short.

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
    field(:take_profit_cents, :integer)
    field(:status, :string, default: "open")
    field(:reject_reason, :string)

    belongs_to(:portfolio, StockFetcher.Trading.Portfolio)
    belongs_to(:order, StockFetcher.Trading.Order)
    belongs_to(:parent, __MODULE__)

    timestamps(type: :utc_datetime)
  end
end
