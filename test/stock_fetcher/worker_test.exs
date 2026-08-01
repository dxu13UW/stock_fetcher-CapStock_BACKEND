defmodule StockFetcher.WorkerTest do
  use ExUnit.Case, async: false
  alias StockFetcher.{Repo, StockPrice, Worker}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Req.Test.set_req_test_to_shared(self())

    Req.Test.stub(StockFetcher, fn conn ->
      Req.Test.json(conn, %{"c" => 150.00})
    end)

    :ok
  end

  describe "handle_info :poll_market" do
    test "fetches quotes for configured tickers and writes records to SQLite" do
      {:ok, open_time, _} = DateTime.from_iso8601("2026-07-31T18:00:00Z")

      Req.Test.stub(StockFetcher, fn conn ->
        Req.Test.json(conn, %{"c" => 150.00})
      end)

      {:ok, pid} =
        start_supervised(
          {Worker,
           schedule_timer: false, test_pid: self(), name: nil, now_fn: fn -> open_time end}
        )

      send(pid, :poll_market)

      assert_receive {:poll_complete, 15_000}, 1000

      prices = Repo.all(StockPrice)
      assert length(prices) > 0

      tickers = Enum.map(prices, & &1.ticker)
      assert "AAPL" in tickers
      assert "MSFT" in tickers
    end

    test "handles API errors gracefully without crashing the worker process" do
      {:ok, open_time, _} = DateTime.from_iso8601("2026-07-31T18:00:00Z")

      Req.Test.stub(StockFetcher, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Too Many Requests")
      end)

      {:ok, pid} =
        start_supervised(
          {Worker,
           schedule_timer: false, test_pid: self(), name: nil, now_fn: fn -> open_time end}
        )

      send(pid, :poll_market)

      assert_receive {:poll_complete, 15_000}, 2000

      assert Process.alive?(pid)
      assert Repo.aggregate(StockPrice, :count, :id) == 0
    end

    test "when market is OPEN: returns standard polling interval (15_000 ms)" do
      # Friday, July 31, 2026 at 2:00 PM ET (18:00 UTC) -> Market is OPEN
      {:ok, open_time, _} = DateTime.from_iso8601("2026-07-31T18:00:00Z")

      {:ok, pid} =
        Worker.start_link(
          name: :test_worker_open,
          schedule_timer: false,
          test_pid: self(),
          now_fn: fn -> open_time end
        )

      send(pid, :poll_market)

      assert_receive {:poll_complete, 15_000}, 2000
    end

    test "when market is CLOSED: calculates multi-hour hibernation interval" do
      # Friday, July 31, 2026 at 5:00 PM ET (21:00 UTC) -> Market is CLOSED
      # Next open is Monday at 9:30 AM ET (64.5 hours = 232_200_000 ms away)
      {:ok, closed_time, _} = DateTime.from_iso8601("2026-07-31T21:00:00Z")

      {:ok, pid} =
        Worker.start_link(
          name: :test_worker_closed,
          schedule_timer: false,
          test_pid: self(),
          now_fn: fn -> closed_time end
        )

      send(pid, :poll_market)

      # 232_200_000 ms
      expected_ms = 64 * 3_600_000 + 30 * 60_000

      assert_receive {:poll_complete, ^expected_ms}, 2000
    end
  end
end
