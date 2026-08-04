defmodule StockFetcher.LTTBTest do
  use ExUnit.Case, async: true
  alias StockFetcher.LTTB

  describe "downsample/2 edge cases" do
    test "returns original dataset when length is less than or equal to threshold" do
      data = [%{x: 1, y: 10.0}, %{x: 2, y: 20.0}]
      assert LTTB.downsample(data, 5) == data
    end

    test "returns original dataset when threshold is less than 3" do
      data = [%{x: 1, y: 10.0}, %{x: 2, y: 20.0}, %{x: 3, y: 30.0}]
      assert LTTB.downsample(data, 2) == data
    end
  end

  describe "downsample/2 algorithm logic" do
    test "downsamples a dataset to exact threshold leength" do
      data =
        for i <- 1..100 do
          %{x: i, y: i * 1.5}
        end

      downsampled = LTTB.downsample(data, 10)
      assert length(downsampled) == 10
    end

    test "strictly preserves the first and last data points" do
      first_pt = %{x: 1, y: 100.0}
      last_pt = %{x: 50, y: 500.0}

      middle =
        for i <- 2..49 do
          %{x: i, y: :rand.uniform() * 100}
        end

      data = [first_pt | middle] ++ [last_pt]
      downsampled = LTTB.downsample(data, 10)

      assert List.first(downsampled) == first_pt
      assert List.last(downsampled) == last_pt
    end

    test "preserves a major spike in the middle of data" do
      flat_left = for i <- 1..20, do: %{x: i, y: 10.0}
      spike = %{x: 21, y: 999.0}
      flat_right = for i <- 22..40, do: %{x: i, y: 10.0}

      data = flat_left ++ [spike] ++ flat_right
      downsampled = LTTB.downsample(data, 5)

      assert Enum.any?(downsampled, fn p -> p.x == 21 and p.y == 999.0 end)
    end
  end
end
