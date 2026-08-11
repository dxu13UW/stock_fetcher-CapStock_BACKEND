defmodule StockFetcherWeb.TelemetryHandlerTest do
  use ExUnit.Case, async: true

  alias StockFetcherWeb.TelemetryHandler
  alias StockFetcher.StockPrice

  @pubsub_topic "stocks:live"

  setup do
    Phoenix.PubSub.subscribe(StockFetcher.PubSub, @pubsub_topic)
    :ok
  end

  describe "handle_event/4" do
    test "broadcasts stock payload over PubSub when telemetry event fires" do
      stock = %StockPrice{
        id: 42,
        ticker: "AAPL",
        price: 185.50,
        inserted_at: DateTime.utc_now()
      }

      :telemetry.execute(
        [:stock_fetcher, :stock_price, :saved],
        %{count: 1},
        %{stock_price: stock}
      )

      assert_receive {"new_price", payload}

      assert payload.id == 42
      assert payload.ticker == "AAPL"
      assert payload.price == 185.50
      assert payload.timestamp == stock.inserted_at
    end
  end
end
