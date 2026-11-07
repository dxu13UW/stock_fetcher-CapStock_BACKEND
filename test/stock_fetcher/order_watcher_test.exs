defmodule StockFetcher.OrderWatcherTest do
  # async: false: writes to SQLite, and the watcher process shares this test's sandbox
  # connection (shared mode), which only works for one test at a time.
  use ExUnit.Case, async: false

  alias StockFetcher.{OrderWatcher, Repo, Trading}
  alias StockFetcher.Trading.PendingOrder

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # A private topic, so Mock.Streamer's real ticks can't interfere.
    topic = "test:prices:#{System.unique_integer([:positive])}"
    name = :"order_watcher_#{System.unique_integer([:positive])}"
    pid = start_supervised!({OrderWatcher, source: :mock, topic: topic, name: name})

    portfolio = Trading.demo_portfolio(:mock)
    Phoenix.PubSub.subscribe(StockFetcher.PubSub, Trading.portfolio_topic(portfolio.id))

    %{topic: topic, pid: pid, name: name, portfolio: portfolio}
  end

  # Broadcasts a tick, then waits until the watcher has handled it: a synchronous call is
  # answered only after every earlier message in its mailbox.
  defp tick(%{topic: topic, pid: pid}, ticker, price) do
    Phoenix.PubSub.broadcast(
      StockFetcher.PubSub,
      topic,
      {"new_price", %{id: 1, ticker: ticker, price: price, timestamp: DateTime.utc_now()}}
    )

    :sys.get_state(pid)
  end

  defp place(portfolio, limit, stop) do
    {:ok, :placed, pending} =
      Trading.place_limit_order(portfolio.id, "ZZW", 10, limit, stop, source: :mock)

    pending
  end

  test "a limit entry waits above the limit, fills below it, then the stop-loss closes it",
       ctx do
    entry = place(ctx.portfolio, 100, 90)

    tick(ctx, "ZZW", 101.0)
    tick(ctx, "ZZW", 100.0)
    assert Repo.get!(PendingOrder, entry.id).status == "open"

    tick(ctx, "ZZW", 99.5)
    assert Repo.get!(PendingOrder, entry.id).status == "filled"

    assert_receive {:pending_order_event, :ok,
                    "Limit order filled: Bought 10 ZZW at $100.00" <> _}

    assert [%PendingOrder{type: "stop", trigger_cents: 9_000} = stop] =
             Trading.list_pending_orders(ctx.portfolio.id)

    tick(ctx, "ZZW", 95.0)
    assert Repo.get!(PendingOrder, stop.id).status == "open"

    tick(ctx, "ZZW", 88.0)
    assert Repo.get!(PendingOrder, stop.id).status == "filled"
    assert_receive {:pending_order_event, :ok, "Stop-loss triggered: Sold 10 ZZW at $88.00" <> _}
    assert Trading.get_portfolio!(ctx.portfolio.id).positions == []
  end

  test "ticks for other tickers and cancelled orders fill nothing", ctx do
    entry = place(ctx.portfolio, 100, nil)

    tick(ctx, "ZZOTHER", 1.0)
    assert Repo.get!(PendingOrder, entry.id).status == "open"

    {:ok, _} = Trading.cancel_pending_order(ctx.portfolio.id, entry.id)
    tick(ctx, "ZZW", 50.0)
    assert Repo.get!(PendingOrder, entry.id).status == "cancelled"
    refute_received {:pending_order_event, _, _}
  end

  test "a mock watcher never fills live orders", ctx do
    live = Trading.demo_portfolio(:live)
    {:ok, :placed, live_order} = Trading.place_limit_order(live.id, "ZZW", 1, 100, nil)

    tick(ctx, "ZZW", 50.0)
    assert Repo.get!(PendingOrder, live_order.id).status == "open"
  end

  test "an order it can't afford is rejected and reported", ctx do
    big = place(ctx.portfolio, 1_000_000, nil)

    tick(ctx, "ZZW", 999_999.0)
    assert Repo.get!(PendingOrder, big.id).status == "rejected"
    assert_receive {:pending_order_event, :error, "Rejected limit buy 10 ZZW" <> _}
  end

  test "after a crash the supervisor restarts it and open orders still fill", ctx do
    entry = place(ctx.portfolio, 100, nil)

    Process.exit(ctx.pid, :kill)
    new_pid = wait_for_restart(ctx.name, ctx.pid)

    tick(%{ctx | pid: new_pid}, "ZZW", 99.0)
    assert Repo.get!(PendingOrder, entry.id).status == "filled"
  end

  # The supervisor (start_supervised!) restarts it under the same registered name.
  defp wait_for_restart(name, old_pid) do
    case GenServer.whereis(name) do
      pid when is_pid(pid) and pid != old_pid ->
        pid

      _ ->
        Process.sleep(10)
        wait_for_restart(name, old_pid)
    end
  end
end
