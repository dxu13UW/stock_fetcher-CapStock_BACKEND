# run_query.exs
alias StockFetcher.Repo
alias StockFetcher.StockPrice

IO.puts("Reading stock prices from SQLite...")

# 1. Fetch all records from the database
prices = Repo.all(StockPrice)

# 2. Transform the database structs into readable formatted strings
file_content =
  prices
  |> Enum.map(fn record ->
    "#{record.inserted_at} | #{record.ticker}: $#{record.price}"
  end)
  |> Enum.join("\n")

# 3. Write the final string block to stock_prices.txt
# By default, File.write with no flags will overwrite.
case File.write("stock_prices.txt", file_content) do
  :ok ->
    IO.puts("✨ Success! Saved #{Enum.count(prices)} records to stock_prices.txt")

  {:error, reason} ->
    IO.puts("❌ Failed to write file: #{inspect(reason)}")
end
