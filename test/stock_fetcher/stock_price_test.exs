defmodule StockFetcher.StockPriceTest do
  use ExUnit.Case, async: true
  alias StockFetcher.StockPrice
  import StockPrice, only: [changeset: 2]
  import StockFetcher.TestHelpers

  describe "StockPrice changeset/2" do
    test "validates required fields" do
      changeset = changeset(%StockPrice{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).ticker
      assert "can't be blank" in errors_on(changeset).price
    end
  end
end
