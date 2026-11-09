defmodule StockFetcher.CandlesTest do
  use ExUnit.Case, async: true

  alias StockFetcher.Candles

  test "fold_tick/4: same bucket widens the candle, a newer one starts a candle, late ticks are ignored" do
    c = Candles.fold_tick(%{}, "ZZ", 60, 10.0)
    c = Candles.fold_tick(c, "ZZ", 60, 12.0)
    c = Candles.fold_tick(c, "ZZ", 60, 9.0)
    c = Candles.fold_tick(c, "ZZ", 60, 11.0)
    assert c["ZZ"] == [%{time: 60, open: 10.0, high: 12.0, low: 9.0, close: 11.0}]

    c = Candles.fold_tick(c, "ZZ", 120, 11.5)
    assert List.last(c["ZZ"]) == %{time: 120, open: 11.5, high: 11.5, low: 11.5, close: 11.5}

    assert Candles.fold_tick(c, "ZZ", 60, 50.0) == c
  end

  test "the mock source starts with history for all 50 tickers, then folds in ticks" do
    {:ok, pid} =
      Candles.start_link(source: :mock, name: :candles_test, topics: ["test:candles"])

    history = Candles.get(:mock, "QBTS", :candles_test)
    assert length(history) == 120

    assert Enum.all?(
             history,
             &(&1.low <= min(&1.open, &1.close) and &1.high >= max(&1.open, &1.close))
           )

    send(pid, {"new_price", %{ticker: "QBTS", price: 11.0, timestamp: DateTime.utc_now()}})
    assert List.last(Candles.get(:mock, "QBTS", :candles_test)).close == 11.0
    assert Candles.get(:mock, "NOPE", :candles_test) == []
  end

  describe "day_open/3" do
    # Mon 2026-11-09: 9:30 ET = 14:30 UTC.
    @open_930 DateTime.to_unix(~U[2026-11-09 14:30:00Z])

    defp c(time, open), do: %{time: time, open: open, high: open, low: open, close: open}

    test "live: the first candle of today's session, not pre-market" do
      candles = [c(@open_930 - 600, 99.0), c(@open_930, 100.0), c(@open_930 + 300, 101.0)]
      now = ~U[2026-11-09 16:00:00Z]

      assert StockFetcher.Candles.day_open(candles, :live, now) ==
               %{price: 100.0, time: @open_930, kind: :session}
    end

    test "live: before 9:30 it measures from the previous session (Friday on a Monday)" do
      friday_930 = DateTime.to_unix(~U[2026-11-06 14:30:00Z])
      candles = [c(friday_930 - 300, 90.0), c(friday_930, 91.0), c(@open_930 - 600, 95.0)]

      assert %{price: 91.0, time: ^friday_930} =
               StockFetcher.Candles.day_open(candles, :live, ~U[2026-11-09 13:00:00Z])
    end

    test "live: nil until the session has a candle; mock: the oldest candle" do
      pre_market = [c(@open_930 - 600, 99.0)]
      assert StockFetcher.Candles.day_open(pre_market, :live, ~U[2026-11-09 14:31:00Z]) == nil
      assert StockFetcher.Candles.day_open([], :live) == nil

      assert StockFetcher.Candles.day_open([c(5, 10.0), c(65, 11.0)], :mock) ==
               %{price: 10.0, time: 5, kind: :mock}
    end
  end

  describe "previous close" do
    alias StockFetcher.Candles

    test "daily_closes/1: a daily bar's New York date is its trading day" do
      raw = %{
        "AAPL" => [
          %{"t" => "2026-11-06T05:00:00Z", "c" => 345.12},
          %{"t" => "2026-11-05T05:00:00Z", "c" => 340}
        ],
        "EMPTY" => []
      }

      assert Candles.daily_closes(raw) == %{
               "AAPL" => [
                 %{date: ~D[2026-11-05], close: 340.0},
                 %{date: ~D[2026-11-06], close: 345.12}
               ]
             }
    end

    test "trading_day/1: today in New York, Friday on a weekend" do
      assert Candles.trading_day(~U[2026-11-09 16:00:00Z]) == ~D[2026-11-09]
      # 11 PM Sunday in New York is still Sunday, even though it's Monday in UTC.
      assert Candles.trading_day(~U[2026-11-09 04:00:00Z]) == ~D[2026-11-06]
      assert Candles.trading_day(~U[2026-11-07 15:00:00Z]) == ~D[2026-11-06]
    end

    test "prev_close/2: yesterday's during the day, Friday's on Monday, Thursday's on a weekend" do
      closes = [
        %{date: ~D[2026-11-05], close: 340.0},
        %{date: ~D[2026-11-06], close: 345.0},
        # Today's partial daily bar is never the "previous" close.
        %{date: ~D[2026-11-09], close: 351.0}
      ]

      # Monday, 8 AM and noon in New York: Friday's close.
      assert %{price: 345.0, date: ~D[2026-11-06]} =
               Candles.prev_close(closes, ~U[2026-11-09 13:00:00Z])

      assert %{price: 345.0} = Candles.prev_close(closes, ~U[2026-11-09 17:00:00Z])
      # Saturday: Thursday's close, so the change is Friday's move.
      assert %{price: 340.0, date: ~D[2026-11-05]} =
               Candles.prev_close(closes, ~U[2026-11-07 15:00:00Z])

      assert Candles.prev_close([], ~U[2026-11-09 17:00:00Z]) == nil
    end
  end
end
