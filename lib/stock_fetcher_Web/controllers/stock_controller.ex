defmodule StockFetcherWeb.StockController do
  use Phoenix.Controller, formats: [:json]

  alias StockFetcher
  alias StockFetcher.Mock

  @watchlist ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]

  @doc """
  GET /api/stocks
  Returns 12 hours of LTTB downsampled historical prices (max 100 points each)
  for core watchlist tickers.
  """
  # Clause 1: Mocking enabled
  def index(conn, %{"mock" => "true"}) do
    data =
      Mock.Hydration.hydrate_watchlist()
      |> format_watchlist()

    json(conn, %{data: data})
  end

  # Clause 2: Actual connection
  def index(conn, _params) do
    data =
      StockFetcher.hydrate_watchlist(@watchlist)
      |> format_watchlist()

    json(conn, %{data: data})
  end

  # --- Internal Helpers ---

  defp format_watchlist(watchlist_map) do
    Map.new(watchlist_map, fn {ticker, prices} ->
      formatted_points =
        Enum.map(prices, fn p ->
          %{
            id: p.id,
            ticker: p.ticker,
            price: normalize_float(p.price),
            timestamp: DateTime.to_unix(p.inserted_at, :millisecond)
          }
        end)

      {ticker, formatted_points}
    end)
  end

  defp normalize_float(%Decimal{} = dec), do: Decimal.to_float(dec)
  defp normalize_float(val) when is_float(val), do: val
  defp normalize_float(val) when is_integer(val), do: val * 1.0
end
