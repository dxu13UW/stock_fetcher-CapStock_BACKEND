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
end
