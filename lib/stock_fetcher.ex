defmodule StockFetcher do
  @moduledoc """
  The core CONTEXT module for managing stock price data, persistence, and database hygiene.
  Contains all core business logic for the application.
  """
  import Ecto.Query
  require Logger
  alias StockFetcher.{Repo, StockPrice, LTTB}

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
        Logger.error("Failed to save stock price: #{inspect(changeset.errors)}")
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

  @doc """
  Fetches historical stock records for `ticker` over the past `hours`,
  downsampling the result set to `target_points` using LTTB.
  """
  def get_hydrated_prices(ticker, hours \\ 12, target_points \\ 100) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-hours, :hour)

    Repo.all(
      from(s in StockPrice,
        where: s.ticker == ^String.upcase(ticker) and s.inserted_at >= ^cutoff,
        order_by: [asc: s.inserted_at]
      )
    )
    |> LTTB.downsample(target_points)
  end

  @doc """
  Hydrates a default or custom list of stock tickers with downsampled historical prices.
  Returns a map keyed by ticker name.
  """
  def hydrate_watchlist(
        tickers \\ ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"],
        hours \\ 12,
        target_points \\ 100
      ) do
    Map.new(tickers, fn ticker ->
      prices = get_hydrated_prices(ticker, hours, target_points)
      {ticker, prices}
    end)
  end
end
