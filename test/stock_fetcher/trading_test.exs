defmodule StockFetcher.TradingTest do
  # async: false: this module writes to SQLite, which has one write lock held by each test's
  # sandbox transaction until it ends; async writers time out with "Database busy".
  use ExUnit.Case, async: false

  alias StockFetcher.{Repo, Trading}
  alias StockFetcher.Trading.{Order, PendingOrder, Portfolio}

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
            :portfolio_not_found,
            :market_closed,
            :invalid_limit,
            :invalid_stop,
            :not_open
          ] do
        assert is_binary(Trading.error_message(reason))
      end
    end
  end

  describe "place_market_order/6 market hours" do
    # 2026-11-04 is a Wednesday; Eastern time is UTC-5 in November.
    @open ~U[2026-11-04 16:00:00Z]
    @after_close ~U[2026-11-04 21:30:00Z]
    @saturday ~U[2026-11-07 16:00:00Z]

    test "live orders fill while the market is open", %{portfolio: p} do
      assert {:ok, _} = Trading.place_market_order(p.id, "buy", "AAPL", 1, 100.0, now: @open)
    end

    test "live orders are rejected after the close and on weekends", %{portfolio: p} do
      for now <- [@after_close, @saturday] do
        assert {:error, :market_closed} =
                 Trading.place_market_order(p.id, "buy", "AAPL", 1, 100.0, now: now)
      end

      assert Trading.get_portfolio!(p.id).cash_cents == Trading.starting_cash_cents()
    end

    test "source defaults to live", %{portfolio: p} do
      assert {:error, :market_closed} =
               Trading.place_market_order(p.id, "buy", "AAPL", 1, 100.0, now: @saturday)

      assert {:error, :market_closed} =
               Trading.place_market_order(p.id, "buy", "AAPL", 1, 100.0,
                 source: :live,
                 now: @saturday
               )
    end

    test "mock orders fill at any time", %{portfolio: p} do
      assert {:ok, _} =
               Trading.place_market_order(p.id, "buy", "AAPL", 1, 100.0,
                 source: :mock,
                 now: @saturday
               )
    end
  end

  describe "demo_portfolio/1" do
    test "mock trades get their own portfolio", %{portfolio: live} do
      mock = Trading.demo_portfolio(:mock)

      assert mock.id != live.id
      assert mock.cash_cents == Trading.starting_cash_cents()
      assert Trading.demo_portfolio(:live).id == live.id
    end
  end

  describe "fill_rule/2" do
    test "limit buy fills only when the price trades below the limit, at the limit" do
      limit = %PendingOrder{type: "limit", side: "buy", trigger_cents: 19_000}

      assert Trading.fill_rule(limit, 19_100) == :wait
      assert Trading.fill_rule(limit, 19_000) == :wait
      assert Trading.fill_rule(limit, 18_999) == {:fill, 19_000}
      assert Trading.fill_rule(limit, 17_000) == {:fill, 19_000}
    end

    test "stop sell fills at or below the stop, at the tick price (gaps included)" do
      stop = %PendingOrder{type: "stop", side: "sell", trigger_cents: 17_700}

      assert Trading.fill_rule(stop, 17_701) == :wait
      assert Trading.fill_rule(stop, 17_700) == {:fill, 17_700}
      assert Trading.fill_rule(stop, 16_500) == {:fill, 16_500}
    end
  end

  describe "place_limit_order/6" do
    test "rests when the price is above the limit", %{portfolio: p} do
      assert {:ok, :placed, pending} =
               Trading.place_limit_order(p.id, "aapl", 3, "190.00", "177", current_price: 195.0)

      assert %PendingOrder{
               ticker: "AAPL",
               type: "limit",
               side: "buy",
               quantity: 3,
               trigger_cents: 19_000,
               stop_cents: 17_700,
               source: "live",
               status: "open"
             } = pending

      assert Trading.list_pending_orders(p.id) |> Enum.map(& &1.id) == [pending.id]
      assert Trading.get_portfolio!(p.id).cash_cents == Trading.starting_cash_cents()
    end

    test "rests when there's no price or the market is closed", %{portfolio: p} do
      assert {:ok, :placed, _} = Trading.place_limit_order(p.id, "AAPL", 1, 190, nil)

      assert {:ok, :placed, _} =
               Trading.place_limit_order(p.id, "AAPL", 1, 190, nil,
                 current_price: 180.0,
                 now: ~U[2026-11-07 16:00:00Z]
               )
    end

    test "fills now at the current price when already below the limit", %{portfolio: p} do
      assert {:ok, :filled, %{order: order, pending: pending, stop: stop}} =
               Trading.place_limit_order(p.id, "AAPL", 2, 190, 177, current_price: 185.0)

      assert order.price_cents == 18_500
      assert pending.status == "filled" and pending.order_id == order.id

      assert %PendingOrder{type: "stop", side: "sell", trigger_cents: 17_700, status: "open"} =
               stop

      assert stop.parent_id == pending.id
    end

    test "validates limit and stop", %{portfolio: p} do
      assert {:error, :invalid_limit} = Trading.place_limit_order(p.id, "AAPL", 1, "", nil)
      assert {:error, :invalid_limit} = Trading.place_limit_order(p.id, "AAPL", 1, "abc", nil)
      assert {:error, :invalid_limit} = Trading.place_limit_order(p.id, "AAPL", 1, 0, nil)
      assert {:error, :invalid_stop} = Trading.place_limit_order(p.id, "AAPL", 1, 190, 190)
      assert {:error, :invalid_stop} = Trading.place_limit_order(p.id, "AAPL", 1, 190, "-1")
      assert {:error, :invalid_quantity} = Trading.place_limit_order(p.id, "AAPL", 0, 190, nil)
      assert Trading.list_pending_orders(p.id) == []
    end
  end

  describe "fill_pending_order/2 and cancel_pending_order/2" do
    setup %{portfolio: p} do
      {:ok, :placed, pending} = Trading.place_limit_order(p.id, "AAPL", 10, 100, 90)
      %{pending: pending}
    end

    test "a fill buys, records the order and opens the stop-loss", %{
      portfolio: p,
      pending: pending
    } do
      assert {:ok, %{order: order, stop: stop}} = Trading.fill_pending_order(pending.id, 10_000)

      assert order.side == "buy" and order.quantity == 10 and order.price_cents == 10_000
      assert Trading.get_portfolio!(p.id).cash_cents == Trading.starting_cash_cents() - 100_000
      assert Trading.list_pending_orders(p.id) |> Enum.map(& &1.id) == [stop.id]

      # The stop-loss closes the position at its fill price.
      assert {:ok, %{order: sold, stop: nil}} = Trading.fill_pending_order(stop.id, 8_800)
      assert sold.side == "sell" and sold.price_cents == 8_800
      assert Trading.get_portfolio!(p.id).positions == []
    end

    test "cancel, then fill: the fill changes nothing", %{portfolio: p, pending: pending} do
      assert {:ok, %PendingOrder{status: "cancelled"}} =
               Trading.cancel_pending_order(p.id, "#{pending.id}")

      assert {:error, :not_open} = Trading.fill_pending_order(pending.id, 9_900)
      assert Trading.get_portfolio!(p.id).cash_cents == Trading.starting_cash_cents()
      assert Repo.aggregate(Order, :count) == 0
    end

    test "fill, then cancel: the cancel is refused", %{portfolio: p, pending: pending} do
      {:ok, _} = Trading.fill_pending_order(pending.id, 9_900)
      assert {:error, :not_open} = Trading.cancel_pending_order(p.id, pending.id)
    end

    test "only the owning portfolio can cancel", %{pending: pending} do
      other = Trading.demo_portfolio(:mock)
      assert {:error, :not_open} = Trading.cancel_pending_order(other.id, pending.id)
      assert {:error, :not_open} = Trading.cancel_pending_order(other.id, "nope")
    end

    test "a fill it can't afford is rejected, not retried", %{portfolio: p} do
      {:ok, :placed, big} = Trading.place_limit_order(p.id, "AAPL", 1, 1_000_000, nil)

      assert {:error, :insufficient_cash} = Trading.fill_pending_order(big.id, 100_000_000)

      assert %PendingOrder{status: "rejected", reject_reason: "insufficient_cash"} =
               Repo.get!(PendingOrder, big.id)
    end

    test "list_open_orders/2 is per source and ticker", %{pending: pending} do
      mock = Trading.demo_portfolio(:mock)
      {:ok, :placed, _} = Trading.place_limit_order(mock.id, "AAPL", 1, 100, nil, source: :mock)

      assert Trading.list_open_orders("live", "AAPL") |> Enum.map(& &1.id) == [pending.id]
      assert Trading.list_open_orders("live", "MSFT") == []
      assert [%PendingOrder{source: "mock"}] = Trading.list_open_orders("mock", "AAPL")
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
