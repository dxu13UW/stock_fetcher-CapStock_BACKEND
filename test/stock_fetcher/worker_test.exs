defmodule StockFetcher.WorkerTest do
  use ExUnit.Case, async: false
  alias StockFetcher.Repo
  alias StockFetcher.StockPrice
  alias StockFetcher.Worker

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Req.Test.set_req_test_to_shared(self())
    :ok
  end

  describe "handle_info :poll_market" do
    test "fetches quotes for configured tickers and writes records to SQLite" do
      Req.Test.stub(StockFetcher, fn conn ->
        Req.Test.json(conn, %{"c" => 150.00})
      end)

      {:ok, pid} = start_supervised({Worker, schedule_timer: false, test_pid: self(), name: nil})
      send(pid, :poll_market)

      assert_receive :poll_complete, 1000

      prices = Repo.all(StockPrice)
      assert length(prices) > 0

      tickers = Enum.map(prices, & &1.ticker)
      assert "AAPL" in tickers
      assert "MSFT" in tickers
    end

    test "handles API errors gracefully without crashing the worker process" do
      Req.Test.stub(StockFetcher, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Too Many Requests")
      end)

      {:ok, pid} = start_supervised({Worker, schedule_timer: false, test_pid: self(), name: nil})

      send(pid, :poll_market)

      assert_receive :poll_complete, 1000

      assert Process.alive?(pid)
      assert Repo.aggregate(StockPrice, :count, :id) == 0
    end
  end
end
