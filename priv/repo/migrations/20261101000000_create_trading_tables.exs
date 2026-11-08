defmodule StockFetcher.Repo.Migrations.CreateTradingTables do
  use Ecto.Migration

  # Paper trading (PLAN.md step C). Money is integer cents; quantities are whole shares.
  def change do
    create table(:portfolios) do
      add :name, :string, null: false
      add :cash_cents, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:portfolios, [:name])

    create table(:positions) do
      add :portfolio_id, references(:portfolios, on_delete: :delete_all), null: false
      add :ticker, :string, null: false
      add :quantity, :integer, null: false
      add :avg_cost_cents, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    # One row per ticker per portfolio; also makes the per-order lookup an index hit.
    create unique_index(:positions, [:portfolio_id, :ticker])

    # Every fill, oldest first. Doubles as trade history (interview item 6).
    create table(:orders) do
      add :portfolio_id, references(:portfolios, on_delete: :delete_all), null: false
      add :ticker, :string, null: false
      add :side, :string, null: false
      add :quantity, :integer, null: false
      add :price_cents, :integer, null: false
      add :total_cents, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:orders, [:portfolio_id])
  end
end
