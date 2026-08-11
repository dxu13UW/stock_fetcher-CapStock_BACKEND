defmodule StockFetcher.Mock.HydrationTest do
  use ExUnit.Case, async: true

  alias StockFetcher.Mock.Hydration

  @expected_tickers ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]

  describe "get_hydrated_prices/3" do
    test "returns downsampled mock records for a single ticker using defaults" do
      prices = Hydration.get_hydrated_prices("aapl")

      assert length(prices) <= 100
      assert length(prices) > 0

      first_point = List.first(prices)
      assert first_point.ticker == "AAPL"
      assert is_float(first_point.price)
      assert %DateTime{} = first_point.inserted_at
      assert is_integer(first_point.id)
    end

    test "generates positive prices along a random-walk trajectory" do
      prices = Hydration.get_hydrated_prices("AAPL", 12, 100)

      Enum.each(prices, fn point ->
        assert is_float(point.price)
        assert point.price > 0.0
      end)
    end

    test "respects custom target_points limit" do
      target_points = 20
      prices = Hydration.get_hydrated_prices("TSLA", 6, target_points)

      assert length(prices) <= target_points
    end

    test "generates records in ascending chronological order" do
      prices = Hydration.get_hydrated_prices("MSFT")

      first_point = List.first(prices)
      last_point = List.last(prices)

      assert DateTime.compare(first_point.inserted_at, last_point.inserted_at) == :lt
    end
  end

  describe "hydrate_watchlist/2" do
    test "returns a map containing all core watchlist tickers" do
      watchlist = Hydration.hydrate_watchlist()

      assert Map.keys(watchlist) -- @expected_tickers == []

      Enum.each(@expected_tickers, fn ticker ->
        prices = Map.fetch!(watchlist, ticker)
        assert is_list(prices)
        assert length(prices) <= 100
        assert length(prices) > 0
      end)
    end

    test "passes custom hours and target_points parameters to all tickers" do
      target_points = 15
      watchlist = Hydration.hydrate_watchlist(6, target_points)

      Enum.each(@expected_tickers, fn ticker ->
        prices = watchlist[ticker]
        assert length(prices) <= target_points
      end)
    end
  end
end
