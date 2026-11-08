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

    test "clamps calculated price updates at the upper bound ($5000.00)" do
      state = %{prices: %{"TSLA" => 5000.00}, enabled: false, topic: @pubsub_topic, per_tick: 1}

      {:noreply, new_state} = Streamer.handle_info(:tick, state)

      assert new_state.prices["TSLA"] <= 5000.00
      assert new_state.prices["TSLA"] >= 1.00
    end

    test "clamps calculated price updates at the lower bound ($1.00)" do
      state = %{prices: %{"TSLA" => 1.00}, enabled: false, topic: @pubsub_topic, per_tick: 1}

      {:noreply, new_state} = Streamer.handle_info(:tick, state)

      assert new_state.prices["TSLA"] >= 1.00
      assert new_state.prices["TSLA"] <= 5000.00
    end
  end

  describe "extra instance (2026-11-07)" do
    test "moves several tickers per tick on its own topic" do
      Phoenix.PubSub.subscribe(StockFetcher.PubSub, "stocks:mock:extra")
      prices = StockFetcher.Tickers.mock_prices(:extra)

      {:ok, pid} =
        Streamer.start_link(
          enabled: false,
          name: nil,
          topic: "stocks:mock:extra",
          prices: prices,
          per_tick: 6
        )

      send(pid, :tick)

      tickers =
        for _ <- 1..6 do
          # Only extra tickers: the app's own streamer may tick AAPL etc. on "stocks:mock".
          assert_receive {"new_price", %{ticker: ticker}} when ticker not in @valid_tickers
          ticker
        end

      assert length(Enum.uniq(tickers)) == 6
      assert Enum.all?(tickers, &Map.has_key?(prices, &1))
    end

    test "current_prices/1 lists every ticker; [] when not running" do
      {:ok, pid} = Streamer.start_link(enabled: false, name: :streamer_prices_test)
      assert length(Streamer.current_prices(:streamer_prices_test)) == 5
      GenServer.stop(pid)
      assert Streamer.current_prices(:streamer_prices_test) == []
    end
  end
end
