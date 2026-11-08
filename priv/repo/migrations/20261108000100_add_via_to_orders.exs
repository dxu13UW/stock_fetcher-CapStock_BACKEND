defmodule StockFetcher.Repo.Migrations.AddViaToOrders do
  use Ecto.Migration

  # How an order was placed (2026-11-07): nil for a manual market order (Buy, Sell, Short,
  # Cover), or "limit_entry" / "take_profit" / "stop_loss" when a resting order filled. Order
  # history shows it, so automatic exits stand out from manual ones.
  def change do
    alter table(:orders) do
      add :via, :string
    end
  end
end
