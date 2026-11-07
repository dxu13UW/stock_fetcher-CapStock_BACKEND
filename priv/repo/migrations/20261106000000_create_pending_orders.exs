defmodule StockFetcher.Repo.Migrations.CreatePendingOrders do
  use Ecto.Migration

  # Resting orders (PLAN.md step G): limit entries and the stop-losses they create.
  # The DB is the source of truth; OrderWatcher reads open rows on each price tick, so a
  # crash or restart loses nothing.
  def change do
    create table(:pending_orders) do
      add :portfolio_id, references(:portfolios, on_delete: :delete_all), null: false
      # "live" or "mock": which price stream may trigger it.
      add :source, :string, null: false
      add :ticker, :string, null: false
      # "limit" (buy entry) or "stop" (sell stop-loss).
      add :type, :string, null: false
      add :side, :string, null: false
      add :quantity, :integer, null: false
      # Limit price for "limit", stop price for "stop".
      add :trigger_cents, :integer, null: false
      # On a limit entry: the stop-loss to create when it fills (optional).
      add :stop_cents, :integer
      # "open" -> "filled" | "cancelled" | "rejected". Only ever changed from "open" by a
      # conditional UPDATE, so cancel and fill can't both win.
      add :status, :string, null: false, default: "open"
      add :reject_reason, :string
      # The fill, once filled.
      add :order_id, references(:orders, on_delete: :nilify_all)
      # The limit entry a stop-loss came from.
      add :parent_id, references(:pending_orders, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # OrderWatcher's per-tick lookup: open orders for one source and ticker.
    create index(:pending_orders, [:source, :ticker, :status])
    create index(:pending_orders, [:portfolio_id, :status])
  end
end
