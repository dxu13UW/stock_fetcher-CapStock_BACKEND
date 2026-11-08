defmodule StockFetcher.Trading.Portfolio do
  @moduledoc """
  A paper-trading account: cash in integer cents plus its positions.

  Two kinds (2026-11-07), told apart by name:
    * `"demo"` / `"demo-mock"`: the shared demo portfolios. The React SPA's API still uses them.
    * `"session:<source>:<random>"`: one per open LiveView tab, private to that tab and deleted
      when it closes (`StockFetcher.Trading.SessionJanitor`). The user keeps it in a save file.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "portfolios" do
    field(:name, :string)
    field(:cash_cents, :integer)
    field(:starting_cash_cents, :integer)

    has_many(:positions, StockFetcher.Trading.Position, preload_order: [asc: :ticker])
    has_many(:orders, StockFetcher.Trading.Order)

    timestamps(type: :utc_datetime)
  end
end
