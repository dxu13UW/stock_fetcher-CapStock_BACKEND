defmodule StockFetcher.Repo.Migrations.AddStartingCashToPortfolios do
  use Ecto.Migration

  # What a portfolio started with (2026-11-07: the user picks $1,000 to $2,000,000), so the page
  # can show total P/L and the save file can carry it. Nullable: the old demo portfolios
  # predate it and are treated as the $100,000 default.
  def change do
    alter table(:portfolios) do
      add :starting_cash_cents, :integer
    end
  end
end
