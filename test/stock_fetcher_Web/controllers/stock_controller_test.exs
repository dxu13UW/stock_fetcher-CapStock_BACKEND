defmodule StockFetcherWeb.StockControllerTest do
  use StockFetcherWeb.ConnCase, async: true
  alias StockFetcher

  setup do
    tickers = ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]

    # Seed database with synthetic records for each ticker
    for ticker <- tickers, i <- 1..120 do
      StockFetcher.save_price(ticker, 100.0 + i)
    end

    :ok
  end

  test "GET /api/stocks returns LTTB hydrated data for all 5 watchlist tickers", %{conn: conn} do
    conn = get(conn, ~p"/api/stocks")

    assert %{"data" => data} = json_response(conn, 200)

    # Check that all 5 tickers are present in the response keys
    assert Map.has_key?(data, "AAPL")
    assert Map.has_key?(data, "AMZN")
    assert Map.has_key?(data, "GOOGL")
    assert Map.has_key?(data, "MSFT")
    assert Map.has_key?(data, "TSLA")

    # Assert downsampling down to 100 points max for AAPL
    aapl_points = data["AAPL"]
    assert length(aapl_points) <= 100
    assert is_float(hd(aapl_points)["price"])
    assert is_integer(hd(aapl_points)["timestamp"])
  end
end
