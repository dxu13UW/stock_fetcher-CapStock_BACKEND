defmodule StockFetcher.Alpaca.PollerTest do
  use ExUnit.Case, async: false

  alias StockFetcher.Alpaca.Poller

  @open ~U[2026-11-04 16:00:00Z]
  @closed ~U[2026-11-07 16:00:00Z]

  defp start(now) do
    Phoenix.PubSub.subscribe(StockFetcher.PubSub, "test:extra")

    pid =
      start_supervised!(
        {Poller,
         name: :poller_test,
         symbols: ["NVDA", "QBTS"],
         topic: "test:extra",
         schedule_timer: false,
         now_fn: fn -> now end}
      )

    Req.Test.allow(StockFetcher, self(), pid)
    pid
  end

  defp stub(trades) do
    Req.Test.stub(StockFetcher, fn conn ->
      assert conn.params["feed"] == "iex"
      assert conn.params["symbols"] == "NVDA,QBTS"
      Req.Test.json(conn, %{"trades" => trades})
    end)
  end

  test "broadcasts each trade in the Worker's payload shape, and only new trades" do
    stub(%{
      "NVDA" => %{"p" => 187.62, "t" => "2026-11-04T15:59:59.123456789Z"},
      "QBTS" => %{"p" => 10, "t" => "2026-11-04T15:59:00Z"}
    })

    pid = start(@open)
    send(pid, :poll)

    assert_receive {"new_price", %{ticker: "NVDA", price: 187.62, timestamp: ts, id: id}}
    assert ts == ~U[2026-11-04 15:59:59Z] and is_integer(id)
    assert_receive {"new_price", %{ticker: "QBTS", price: 10.0}}
    assert length(Poller.latest(:poller_test)) == 2

    # Same trades again: nothing new to say.
    send(pid, :poll)
    :sys.get_state(pid)
    refute_receive {"new_price", _}, 50
  end

  test "polls once at startup even when the market is closed, then waits for the open" do
    stub(%{"NVDA" => %{"p" => 1.0, "t" => "2026-11-06T20:59:00Z"}})
    pid = start(@closed)

    send(pid, :poll)
    assert_receive {"new_price", %{ticker: "NVDA"}}

    stub(%{"NVDA" => %{"p" => 2.0, "t" => "2026-11-07T15:00:00Z"}})
    send(pid, :poll)
    :sys.get_state(pid)
    refute_receive {"new_price", _}, 50
  end

  test "an HTTP error keeps the last prices" do
    Req.Test.stub(StockFetcher, fn conn -> Plug.Conn.send_resp(conn, 403, "forbidden") end)
    pid = start(@open)
    send(pid, :poll)
    :sys.get_state(pid)
    assert Poller.latest(:poller_test) == []
  end
end
