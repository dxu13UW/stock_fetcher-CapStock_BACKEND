defmodule StockFetcher do
  @moduledoc """
  Fetches stock data and inserts it directly into the SQLite database.
  """
  alias StockFetcher.Repo
  alias StockFetcher.StockPrice

  @doc """
  Call this function with a ticker and price to save it to your SQLite database.
  Example: StockFetcher.save_price("AAPL", 175.50)
  """
  def save_price(ticker, price) do
    # 1. Create a data structure mapping your inputs to schema fields
    data_attrs = %{
      ticker: String.upcase(ticker),
      price: price
    }

    # 2. Pass it through the changeset validation logic
    %StockPrice{}
    |> StockPrice.changeset(data_attrs)
    # 3. Write it directly to the database file
    |> Repo.insert()
    |> case do
      {:ok, struct} ->
        IO.puts("Successfully saved #{struct.ticker} at $#{struct.price} to SQLite!")
        {:ok, struct}

      {:error, changeset} ->
        IO.inspect(changeset.errors, label: "Failed to save stock price")
        {:error, changeset}
    end
  end
end
