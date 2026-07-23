defmodule StockFetcher do
  @moduledoc """
  Fetches stock data and inserts it directly into the SQLite database.
  """
  alias StockFetcher.Repo
  alias StockFetcher.StockPrice

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
