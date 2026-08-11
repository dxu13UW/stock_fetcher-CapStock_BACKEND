defmodule StockFetcher.Mock.StreamerTest do
  use ExUnit.Case, async: true

  alias StockFetcher.Mock.Streamer

  @pubsub_topic "stocks:mock"
  @valid_tickers ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]

  setup do
    # Subscribe the test runner process (self()) to the PubSub topic
    Phoenix.PubSub.subscribe(StockFetcher.PubSub, @pubsub_topic)

    # Start an isolated Streamer GenServer instance with enabled: false
    # to disable background timers during unit tests
    {:ok, pid} = Streamer.start_link(enabled: false, name: nil)

    %{streamer: pid}
  end

  describe "handle_info(:tick, state)" do
    test "broadcasts a valid new_price payload over PubSub when triggered", %{streamer: pid} do
      send(pid, :tick)

      assert_receive {"new_price", payload}

      assert is_integer(payload.id)
      assert payload.ticker in @valid_tickers
      assert is_float(payload.price)
      assert payload.price >= 1.00 and payload.price <= 1000.00
      assert %DateTime{} = payload.timestamp
    end

    test "emits sequential random-walk price updates", %{streamer: pid} do
      send(pid, :tick)
      assert_receive {"new_price", first_tick}

      send(pid, :tick)
      assert_receive {"new_price", second_tick}

      assert first_tick.id != second_tick.id
      assert %DateTime{} = first_tick.timestamp
      assert %DateTime{} = second_tick.timestamp
    end

    test "clamps calculated price updates at the upper bound ($1000.00)" do
      state = %{prices: %{"TSLA" => 1000.00}, enabled: false}

      {:noreply, new_state} = Streamer.handle_info(:tick, state)

      assert new_state.prices["TSLA"] <= 1000.00
      assert new_state.prices["TSLA"] >= 1.00
    end

    test "clamps calculated price updates at the lower bound ($1.00)" do
      state = %{prices: %{"TSLA" => 1.00}, enabled: false}

      {:noreply, new_state} = Streamer.handle_info(:tick, state)

      assert new_state.prices["TSLA"] >= 1.00
      assert new_state.prices["TSLA"] <= 1000.00
    end
  end
end
