defmodule StockFetcherWeb.StockControllerTest do
  use StockFetcherWeb.ConnCase, async: true
  alias StockFetcher.{Repo, StockPrice}

  setup do
    :ok
  end

  describe "GET /api/stocks" do
    test "returns 200 OK with formatted stock data and CORS headers", %{conn: conn} do
      Repo.insert!(%StockPrice{ticker: "AAPL", price: 333.02})

      conn =
        conn
        |> put_req_header("origin", "http://localhost:5173")
        |> get(~p"/api/stocks")

      assert json_response(conn, 200) == %{
               "data" => [
                 %{
                   "id" => Repo.one!(StockPrice).id,
                   "ticker" => "AAPL",
                   "price" => 333.02,
                   "timestamp" => DateTime.to_iso8601(Repo.one!(StockPrice).inserted_at)
                 }
               ]
             }

      # Verify CORS header plug behavior
      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:5173"]
    end

    test "limits results to 50 items max", %{conn: conn} do
      # Seed 60 records
      for i <- 1..60 do
        Repo.insert!(%StockPrice{ticker: "STOCK_#{i}", price: 100.0 + i})
      end

      conn = get(conn, ~p"/api/stocks")
      %{"data" => stocks} = json_response(conn, 200)

      assert length(stocks) == 50
    end
  end
end
