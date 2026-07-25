defmodule StockFetcher do
  @moduledoc """
  The core context module for managing stock price data, persistence, and database hygiene.
  Contains all core business logic for the application.
  """
  import Ecto.Query

  alias StockFetcher.{Repo, StockPrice}

  @doc """
  Fetches stock market data for a given ticker from Finnhub API.
  Accepts optional `opts` keyword list (used to pass `Req.Test` plug options during tests).
  """
  def fetch_stock_data(ticker, opts \\ []) do
    token = System.get_env("FINNHUB_API_TOKEN", "test_token")
    url = "https://finnhub.io/api/v1/quote?symbol=#{ticker}&token=#{token}"

    # Fetch configured options for Req.
    # (defaults to [] in dev/prod, uses test plug in test env)
    req_opts = Application.get_env(:stock_fetcher, :req_options, []) |> Keyword.merge(opts)

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: %{"c" => price}}}
      when is_number(price) and price > 0 ->
        {:ok, ticker, price}

      {:ok, %Req.Response{status: 401}} ->
        {:error, ticker, "Invalid API Key"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, ticker, "Rate Limit Reached"}

      {:ok, %Req.Response{status: status}} ->
        {:error, ticker, "HTTP Error #{status}"}

      {:error, exception} ->
        {:error, ticker, "Network Failure: #{inspect(exception)}"}
    end
  end

  @doc """
  Call this function with a ticker and price to save it to your SQLite database.
  Example: StockFetcher.save_price("AAPL", 175.50)
  """
  def save_price(ticker, price) do
    data_attrs = %{
      ticker: String.upcase(ticker),
      price: price
    }

    %StockPrice{}
    |> StockPrice.changeset(data_attrs)
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

  @doc """
  Deletes stock price records that were inserted more than `days_old` days ago.
  """
  def prune_old_prices(days_old) when is_integer(days_old) and days_old > 0 do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-days_old * 86_400, :second)

    query =
      from(p in StockPrice,
        where: p.inserted_at < ^cutoff_time
      )

    Repo.delete_all(query)
  end

  @doc """
  Calculates the current size of the SQLite database in bytes.
  """
  def get_db_size do
    %{rows: [[page_count]]} = Repo.query!("PRAGMA page_count;")
    %{rows: [[page_size]]} = Repo.query!("PRAGMA page_size;")

    page_count * page_size
  end

  @doc """
  Deletes the oldest percentage (e.g., 25%) of stock price records from the database.
  """
  def prune_oldest_percent(percent) when percent > 0 and percent <= 100 do
    total_count = Repo.aggregate(StockPrice, :count, :id)

    if total_count > 0 do
      limit = max(1, trunc(total_count * (percent / 100)))

      # Subquery to find the IDs of the oldest records
      oldest_ids_query =
        from(p in StockPrice,
          order_by: [asc: p.inserted_at],
          limit: ^limit,
          select: p.id
        )

      from(p in StockPrice, where: p.id in subquery(oldest_ids_query))
      |> Repo.delete_all()
    else
      {0, nil}
    end
  end
end
