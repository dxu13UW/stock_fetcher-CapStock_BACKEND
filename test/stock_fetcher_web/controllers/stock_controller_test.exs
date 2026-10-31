defmodule StockFetcherWeb.StockControllerTest do
  use StockFetcherWeb.ConnCase, async: true

  alias StockFetcher.{MarketHours, Repo, StockPrice}

  setup do
    tickers = ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]
    {session_start, _session_end} = MarketHours.get_intraday_bounds()

    entries =
      for ticker <- tickers, i <- 1..250 do
        timestamp =
          session_start
          |> DateTime.add(i * 60, :second)
          |> DateTime.truncate(:second)

        %{
          ticker: ticker,
          price: 100.0 + i,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end

    Repo.insert_all(StockPrice, entries)

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

    # Assert downsampling down to 200 points max for AAPL
    aapl_points = data["AAPL"]
    assert length(aapl_points) <= 200
    assert length(aapl_points) > 0
    assert is_float(hd(aapl_points)["price"])
    assert is_integer(hd(aapl_points)["timestamp"])
  end
end
