defmodule StockFetcher.Trading.SessionPortfolioTest do
  use ExUnit.Case, async: false

  alias StockFetcher.{Repo, Trading}
  alias StockFetcher.Trading.{Portfolio, Position, SessionJanitor}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "create_session_portfolio/2" do
    test "starts with the chosen buying power" do
      assert {:ok, p} = Trading.create_session_portfolio(:mock, "250,000")
      assert p.cash_cents == 25_000_000
      assert Trading.starting_cash(p) == 25_000_000
      assert "session:mock:" <> _ = p.name
      assert p.positions == []
    end

    test "defaults to $100,000; each call is a different portfolio" do
      {:ok, a} = Trading.create_session_portfolio(:live)
      {:ok, b} = Trading.create_session_portfolio(:live)
      assert a.cash_cents == 10_000_000
      assert a.id != b.id
    end

    test "$1,000 to $2,000,000 only" do
      assert {:ok, _} = Trading.create_session_portfolio(:mock, "1000")
      assert {:ok, _} = Trading.create_session_portfolio(:mock, 2_000_000)
      assert {:error, :invalid_starting_cash} = Trading.create_session_portfolio(:mock, "999.99")

      assert {:error, :invalid_starting_cash} =
               Trading.create_session_portfolio(:mock, "2000000.01")

      assert {:error, :invalid_starting_cash} = Trading.create_session_portfolio(:mock, "lots")
      assert {:error, :invalid_starting_cash} = Trading.create_session_portfolio(:mock, nil)
    end
  end

  test "delete_session_portfolio/1 cascades but never touches a demo portfolio" do
    {:ok, p} = Trading.create_session_portfolio(:mock)
    {:ok, _} = Trading.place_market_order(p.id, "buy", "AAPL", 1, 10.0, source: :mock)
    demo = Trading.demo_portfolio(:mock)

    assert Trading.delete_session_portfolio(p.id) == 1
    assert Trading.delete_session_portfolio(demo.id) == 0
    refute Repo.get(Portfolio, p.id)
    assert Repo.aggregate(Position, :count) == 0
    assert Repo.get(Portfolio, demo.id)
  end

  test "account_value_cents/2 counts longs at the price and shorts at what covering returns" do
    {:ok, p} = Trading.create_session_portfolio(:mock, "10000")
    {:ok, _} = Trading.place_market_order(p.id, "buy", "AAPL", 10, 100.0, source: :mock)

    {:ok, %{portfolio: p}} =
      Trading.place_market_order(p.id, "short", "QBTS", 100, 10.0, source: :mock)

    # Cash 10,000 - 1,000 - 1,000 = 8,000. AAPL up $10 (+100), QBTS down $1 (+100 on the short).
    prices = %{"AAPL" => 11_000, "QBTS" => 900}
    assert Trading.account_value_cents(p, &prices[&1]) == 1_020_000
    # No prices: positions count at cost, so the value is the starting cash.
    assert Trading.account_value_cents(p, fn _ -> nil end) == 1_000_000
  end

  test "SessionJanitor deletes the portfolio when its tab's process exits" do
    janitor = start_supervised!({SessionJanitor, name: :janitor_test, sweep: false})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), janitor)

    {:ok, p} = Trading.create_session_portfolio(:mock)
    tab = spawn(fn -> receive do: (:close -> :ok) end)
    SessionJanitor.register(p.id, tab, :janitor_test)
    :sys.get_state(janitor)
    assert Repo.get(Portfolio, p.id)

    send(tab, :close)
    # Wait for the :DOWN to be handled.
    Process.sleep(20)
    :sys.get_state(janitor)
    refute Repo.get(Portfolio, p.id)
  end

  test "open_order_groups/1: a bracket's exits together (highest first), then waiting entries" do
    {:ok, p} = Trading.create_session_portfolio(:mock)

    {:ok, :filled, _} =
      Trading.place_limit_order(p.id, "NVDA", 2, "190", "180",
        take_profit: "200",
        source: :mock,
        current_price: 189.0
      )

    {:ok, :filled, _} =
      Trading.place_limit_order(p.id, "QBTS", 5, "10", "11",
        direction: "short",
        source: :mock,
        current_price: 10.5
      )

    {:ok, :placed, waiting} =
      Trading.place_limit_order(p.id, "MSFT", 1, "390", nil, source: :mock, current_price: 400.0)

    [short, long, entry] = Trading.open_order_groups(p.id)

    assert %{kind: :bracket, direction: :long, ticker: "NVDA", quantity: 2, entry_cents: 18_900} =
             long

    assert Enum.map(long.exits, &{&1.type, &1.trigger_cents}) == [
             {"limit", 20_000},
             {"stop", 18_000}
           ]

    assert %{kind: :bracket, direction: :short, ticker: "QBTS", entry_cents: 1050} = short
    assert [%{type: "stop", trigger_cents: 1100}] = short.exits
    assert %{kind: :entry, order: %{id: id}} = entry
    assert id == waiting.id
  end

  test "fills record how they were placed in orders.via" do
    {:ok, p} = Trading.create_session_portfolio(:mock)

    {:ok, %{order: manual}} =
      Trading.place_market_order(p.id, "buy", "AAPL", 1, 10.0, source: :mock)

    assert manual.via == nil

    {:ok, :placed, entry} =
      Trading.place_limit_order(p.id, "NVDA", 1, "190", "180",
        take_profit: "200",
        source: :mock,
        current_price: 195.0
      )

    {:ok, %{order: filled, stop: stop}} = Trading.fill_pending_order(entry.id, 19_000)
    assert filled.via == "limit_entry"

    {:ok, %{order: stopped}} = Trading.fill_pending_order(stop.id, 17_900)
    assert stopped.via == "stop_loss"
  end
end
