defmodule StockFetcher.TradingTest do
  # async: false: this module writes to SQLite, which has one write lock held by each test's
  # sandbox transaction until it ends; async writers time out with "Database busy".
  use ExUnit.Case, async: false

  alias StockFetcher.{Repo, Trading}
  alias StockFetcher.Trading.{Order, Portfolio}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{portfolio: Trading.demo_portfolio()}
  end

  describe "demo_portfolio/0" do
    test "starts with $100,000 and no positions", %{portfolio: portfolio} do
      assert portfolio.cash_cents == 10_000_000
      assert portfolio.positions == []
    end

    test "returns the same portfolio on every call", %{portfolio: portfolio} do
      assert Trading.demo_portfolio().id == portfolio.id
      assert Repo.aggregate(Portfolio, :count) == 1
    end
  end

  describe "place_market_order/5 buy" do
    test "debits cash, opens a position, and records the order", %{portfolio: p} do
      assert {:ok, %{order: order, portfolio: p2}} =
               Trading.place_market_order(p.id, "buy", "aapl", 10, 189.57)

      # 189.57 * 100 is 18956.999... as a float; Decimal makes it exactly 18957.
      assert order.price_cents == 18_957
      assert order.total_cents == 189_570
      assert %Order{side: "buy", ticker: "AAPL", quantity: 10} = order
      assert p2.cash_cents == 10_000_000 - 189_570
      assert [%{ticker: "AAPL", quantity: 10, avg_cost_cents: 18_957}] = p2.positions
    end

    test "averages the cost across buys, in whole cents", %{portfolio: p} do
      {:ok, _} = Trading.place_market_order(p.id, "buy", "AAPL", 1, 100.00)
      {:ok, %{portfolio: p2}} = Trading.place_market_order(p.id, "buy", "AAPL", 2, 100.01)

      # (10_000 + 2 * 10_001) / 3 = 10_000.67 -> 10_001
      assert [%{quantity: 3, avg_cost_cents: 10_001}] = p2.positions
    end

    test "accepts a quantity string from a form", %{portfolio: p} do
      assert {:ok, %{order: %{quantity: 5}}} =
               Trading.place_market_order(p.id, "buy", "MSFT", " 5 ", 400.0)
    end

    test "rejects an order that costs more than the cash", %{portfolio: p} do
      assert {:error, :insufficient_cash} =
               Trading.place_market_order(p.id, "buy", "TSLA", 1_000, 250.0)

      assert Trading.get_portfolio!(p.id).cash_cents == 10_000_000
      assert Trading.list_orders(p.id) == []
    end

    test "allows spending exactly all the cash", %{portfolio: p} do
      assert {:ok, %{portfolio: %{cash_cents: 0}}} =
               Trading.place_market_order(p.id, "buy", "AMZN", 1_000, 100.0)
    end
  end

  describe "place_market_order/5 sell" do
    setup %{portfolio: p} do
      {:ok, _} = Trading.place_market_order(p.id, "buy", "AAPL", 10, 100.0)
      :ok
    end

    test "credits cash, reduces the position, keeps the average cost", %{portfolio: p} do
      assert {:ok, %{portfolio: p2}} = Trading.place_market_order(p.id, "sell", "AAPL", 4, 110.0)

      assert p2.cash_cents == 10_000_000 - 100_000 + 44_000
      assert [%{quantity: 6, avg_cost_cents: 10_000}] = p2.positions
    end

    test "removes a position that is fully sold", %{portfolio: p} do
      assert {:ok, %{portfolio: p2}} = Trading.place_market_order(p.id, :sell, "AAPL", 10, 100.0)
      assert p2.positions == []
    end

    test "rejects selling more than held", %{portfolio: p} do
      assert {:error, :insufficient_shares} =
               Trading.place_market_order(p.id, "sell", "AAPL", 11, 100.0)

      assert [%{quantity: 10}] = Trading.get_portfolio!(p.id).positions
    end

    test "rejects selling a ticker that isn't held", %{portfolio: p} do
      assert {:error, :insufficient_shares} =
               Trading.place_market_order(p.id, "sell", "MSFT", 1, 400.0)
    end
  end

  describe "place_market_order/5 validation" do
    test "unknown ticker (no price) or blank ticker", %{portfolio: p} do
      assert {:error, :unknown_ticker} = Trading.place_market_order(p.id, "buy", "ZZZZ", 1, nil)
      assert {:error, :unknown_ticker} = Trading.place_market_order(p.id, "buy", "  ", 1, 10.0)
    end

    test "quantity must be a positive whole number", %{portfolio: p} do
      for bad <- [0, -1, "0", "1.5", "abc", "", nil, 1.0] do
        assert {:error, :invalid_quantity} =
                 Trading.place_market_order(p.id, "buy", "AAPL", bad, 10.0),
               "expected #{inspect(bad)} to be rejected"
      end
    end

    test "side must be buy or sell", %{portfolio: p} do
      assert {:error, :invalid_side} = Trading.place_market_order(p.id, "short", "AAPL", 1, 10.0)
    end

    test "price must be positive", %{portfolio: p} do
      assert {:error, :invalid_price} = Trading.place_market_order(p.id, "buy", "AAPL", 1, 0.0)
      assert {:error, :invalid_price} = Trading.place_market_order(p.id, "buy", "AAPL", 1, "10")
    end

    test "missing portfolio" do
      assert {:error, :portfolio_not_found} =
               Trading.place_market_order(-1, "buy", "AAPL", 1, 10.0)
    end

    test "every error has a message" do
      for reason <- [
            :insufficient_cash,
            :insufficient_shares,
            :unknown_ticker,
            :invalid_quantity,
            :invalid_side,
            :invalid_price,
            :portfolio_not_found
          ] do
        assert is_binary(Trading.error_message(reason))
      end
    end
  end

  describe "list_orders/1" do
    test "returns fills newest first", %{portfolio: p} do
      {:ok, _} = Trading.place_market_order(p.id, "buy", "AAPL", 2, 100.0)
      {:ok, _} = Trading.place_market_order(p.id, "sell", "AAPL", 1, 101.0)

      assert [%{side: "sell"}, %{side: "buy"}] = Trading.list_orders(p.id)
    end
  end
end
