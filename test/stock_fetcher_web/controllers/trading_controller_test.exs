defmodule StockFetcherWeb.TradingControllerTest do
  # async: false: this module writes to SQLite (see stock_controller_test.exs).
  use StockFetcherWeb.ConnCase, async: false

  alias StockFetcher.{Repo, StockPrice, Trading}

  # Prices come from the stock_prices table, as if the Worker had saved them.
  defp save_price(ticker, price), do: Repo.insert!(%StockPrice{ticker: ticker, price: price})

  defp post_order(conn, body), do: post(conn, ~p"/api/orders", body)

  # The request can't carry `now:`, so override the test clock from config/test.exs for one
  # test. Safe because this module is async: false.
  defp pin_clock(now) do
    previous = Application.get_env(:stock_fetcher, :trading_fixed_now)
    Application.put_env(:stock_fetcher, :trading_fixed_now, now)
    on_exit(fn -> Application.put_env(:stock_fetcher, :trading_fixed_now, previous) end)
  end

  describe "GET /api/portfolio" do
    test "starts with the demo cash, no positions and no orders", %{conn: conn} do
      body = conn |> get(~p"/api/portfolio") |> json_response(200)

      assert body["portfolio"] == %{
               "cash_cents" => Trading.starting_cash_cents(),
               "positions" => [],
               "orders" => []
             }
    end
  end

  describe "POST /api/orders" do
    test "buys at the newest saved price and returns order, portfolio and message", %{conn: conn} do
      save_price("ZZAPI", 9.0)
      save_price("ZZAPI", 10.0)

      body =
        conn
        |> post_order(%{ticker: "zzapi", side: "buy", quantity: 3})
        |> json_response(201)

      assert body["message"] == "Bought 3 ZZAPI at $10.00 ($30.00)"

      assert %{"ticker" => "ZZAPI", "side" => "buy", "quantity" => 3, "price_cents" => 1000} =
               body["order"]

      assert body["portfolio"]["cash_cents"] == Trading.starting_cash_cents() - 3000

      assert body["portfolio"]["positions"] == [
               %{"ticker" => "ZZAPI", "quantity" => 3, "avg_cost_cents" => 1000}
             ]

      assert [%{"id" => id}] = body["portfolio"]["orders"]
      assert id == body["order"]["id"]
    end

    test "ignores a price sent by the client", %{conn: conn} do
      save_price("ZZAPI", 10.0)

      body =
        conn
        |> post_order(%{ticker: "ZZAPI", side: "buy", quantity: 1, price: 0.01})
        |> json_response(201)

      assert body["order"]["price_cents"] == 1000
    end

    test "accepts quantity as a string (form-style JSON)", %{conn: conn} do
      save_price("ZZAPI", 10.0)

      body =
        conn |> post_order(%{ticker: "ZZAPI", side: "buy", quantity: "2"}) |> json_response(201)

      assert body["order"]["quantity"] == 2
    end

    test "sells shares already held", %{conn: conn} do
      save_price("ZZAPI", 10.0)
      post_order(conn, %{ticker: "ZZAPI", side: "buy", quantity: 3})
      save_price("ZZAPI", 12.0)

      body =
        build_conn()
        |> post_order(%{ticker: "ZZAPI", side: "sell", quantity: 2})
        |> json_response(201)

      assert body["message"] == "Sold 2 ZZAPI at $12.00 ($24.00)"
      assert [%{"quantity" => 1}] = body["portfolio"]["positions"]
    end

    # --- Errors: 422 with a machine-readable code and the same text the LiveView panel shows ---

    test "insufficient cash", %{conn: conn} do
      save_price("ZZAPI", 1_000_000.0)

      body =
        conn |> post_order(%{ticker: "ZZAPI", side: "buy", quantity: 1}) |> json_response(422)

      assert body == %{
               "error" => "insufficient_cash",
               "message" => Trading.error_message(:insufficient_cash)
             }
    end

    test "selling more than held", %{conn: conn} do
      save_price("ZZAPI", 10.0)

      body =
        conn |> post_order(%{ticker: "ZZAPI", side: "sell", quantity: 1}) |> json_response(422)

      assert body == %{
               "error" => "insufficient_shares",
               "message" => Trading.error_message(:insufficient_shares)
             }
    end

    test "unknown ticker (no saved price)", %{conn: conn} do
      body = conn |> post_order(%{ticker: "NOPE", side: "buy", quantity: 1}) |> json_response(422)

      assert body == %{
               "error" => "unknown_ticker",
               "message" => Trading.error_message(:unknown_ticker)
             }
    end

    test "invalid quantity and side", %{conn: conn} do
      save_price("ZZAPI", 10.0)

      assert %{"error" => "invalid_quantity"} =
               conn
               |> post_order(%{ticker: "ZZAPI", side: "buy", quantity: 0})
               |> json_response(422)

      assert %{"error" => "invalid_side"} =
               build_conn()
               |> post_order(%{ticker: "ZZAPI", side: "short", quantity: 1})
               |> json_response(422)
    end

    test "market closed (the API always trades live prices)", %{conn: conn} do
      save_price("ZZAPI", 10.0)
      pin_clock(~U[2026-11-07 16:00:00Z])

      body =
        conn |> post_order(%{ticker: "ZZAPI", side: "buy", quantity: 1}) |> json_response(422)

      assert body == %{
               "error" => "market_closed",
               "message" => Trading.error_message(:market_closed)
             }
    end

    test "a failed order changes nothing", %{conn: conn} do
      save_price("ZZAPI", 10.0)
      post_order(conn, %{ticker: "ZZAPI", side: "sell", quantity: 5})

      body = build_conn() |> get(~p"/api/portfolio") |> json_response(200)

      assert body["portfolio"]["cash_cents"] == Trading.starting_cash_cents()
      assert body["portfolio"]["orders"] == []
    end
  end

  describe "CORS" do
    test "answers the browser's preflight for the React origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://tinle-ri.github.io")
        |> put_req_header("access-control-request-method", "POST")
        |> put_req_header("access-control-request-headers", "content-type")
        |> options(~p"/api/orders")

      assert conn.status in [200, 204]

      assert get_resp_header(conn, "access-control-allow-origin") == [
               "https://tinle-ri.github.io"
             ]
    end
  end
end
