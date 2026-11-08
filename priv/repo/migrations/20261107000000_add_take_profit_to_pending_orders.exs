defmodule StockFetcher.Repo.Migrations.AddTakeProfitToPendingOrders do
  use Ecto.Migration

  # Brackets (2026-11-07): a limit entry can carry a take-profit as well as a stop-loss.
  # When the entry fills, both exits are created; when one exit fills, the other is cancelled
  # (OCO). Nullable: entries without a take-profit leave it empty, and old rows stay valid.
  def change do
    alter table(:pending_orders) do
      add :take_profit_cents, :integer
    end
  end
end
