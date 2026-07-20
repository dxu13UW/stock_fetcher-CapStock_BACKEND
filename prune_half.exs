import Ecto.Query
alias StockFetcher.{Repo, StockPrice}

total_records = Repo.aggregate(StockPrice, :count, :id)
half_count = div(total_records, 2)

IO.puts("📊 Total records in DB: #{total_records}")

if half_count > 0 do
  IO.puts("✂️ Pruning the oldest #{half_count} records...")

  threshold_id =
    StockPrice
    |> order_by(asc: :id)
    |> limit(1)
    |> offset(^half_count)
    |> select([s], s.id)
    |> Repo.one()

if threshold_id do
    {deleted_count, _} =
      from(s in StockPrice, where: s.id < ^threshold_id)
      |> Repo.delete_all()

    IO.puts("✅ Successfully deleted #{deleted_count} old rows!")
  end
else
  IO.puts("🫙 Database too small to prune yet.")
end

IO.puts("🗜️ Forcing SQLite to checkpoint WAL logs and vacuum space...")
Ecto.Adapters.SQL.query!(Repo, "PRAGMA wal_checkpoint(TRUNCATE);", [])
Ecto.Adapters.SQL.query!(Repo, "VACUUM;", [])

IO.puts("🎉 Optimization complete! Check Docker for file size.")
