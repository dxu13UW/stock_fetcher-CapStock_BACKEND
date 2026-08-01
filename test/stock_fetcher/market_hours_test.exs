defmodule StockFetcher.MarketHoursTest do
  use ExUnit.Case, async: true

  alias StockFetcher.MarketHours

  describe "market_open?/1" do
    test "returns true during standard trading hours on a weekday (e.g., Friday at 2:00 PM ET)" do
      # Friday, July 31, 2026 at 18:00 UTC = 2:00 PM EDT
      {:ok, dt, _} = DateTime.from_iso8601("2026-07-31T18:00:00Z")

      assert MarketHours.market_open?(dt) == true
    end

    test "returns true right at market open (9:30 AM ET)" do
      # Friday at 13:30 UTC = 9:30 AM EDT
      {:ok, open_time, _} = DateTime.from_iso8601("2026-07-31T13:30:00Z")

      assert MarketHours.market_open?(open_time) == true
    end

    test "returns true right at market close (4:00 PM ET)" do
      # Friday at 20:00 UTC = 4:00 PM EDT
      {:ok, close_time, _} = DateTime.from_iso8601("2026-07-31T20:00:00Z")

      assert MarketHours.market_open?(close_time) == true
    end

    test "returns false before market open (e.g., 9:15 AM ET)" do
      # Friday at 13:15 UTC = 9:15 AM EDT
      {:ok, pre_market, _} = DateTime.from_iso8601("2026-07-31T13:15:00Z")

      assert MarketHours.market_open?(pre_market) == false
    end

    test "returns false after market close (e.g., 4:15 PM ET)" do
      # Friday at 20:15 UTC = 4:15 PM EDT
      {:ok, after_hours, _} = DateTime.from_iso8601("2026-07-31T20:15:00Z")

      assert MarketHours.market_open?(after_hours) == false
    end

    test "returns false on weekends (e.g., Saturday at 2:00 PM ET)" do
      # Saturday, August 1, 2026 at 18:00 UTC = 2:00 PM EDT
      {:ok, weekend, _} = DateTime.from_iso8601("2026-08-01T18:00:00Z")

      assert MarketHours.market_open?(weekend) == false
    end
  end
end
