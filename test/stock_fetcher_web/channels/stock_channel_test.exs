defmodule StockFetcherWeb.StockChannelTest do
  use StockFetcherWeb.ChannelCase, async: true

  alias StockFetcherWeb.StockChannel

  describe "joining channels" do
    test "successfully joins 'stocks:live' route" do
      assert {:ok, _reply, _socket} =
               subscribe_and_join(
                 socket(StockFetcherWeb.UserSocket, "user_id", %{}),
                 StockChannel,
                 "stocks:live"
               )
    end

    test "successfully joins 'stocks:mock' route" do
      assert {:ok, _reply, _socket} =
               subscribe_and_join(
                 socket(StockFetcherWeb.UserSocket, "user_id", %{}),
                 StockChannel,
                 "stocks:mock"
               )
    end
  end

  describe "pubsub streaming on 'stocks:live'" do
    setup do
      {:ok, _reply, socket} =
        subscribe_and_join(
          socket(StockFetcherWeb.UserSocket, "user_id", %{}),
          StockChannel,
          "stocks:live"
        )

      %{socket: socket}
    end

    test "pushes new_price event down socket when PubSub receives a live tick", %{socket: _socket} do
      payload = %{
        id: 1,
        ticker: "NVDA",
        price: 125.50,
        timestamp: DateTime.utc_now()
      }

      # Broadcast using exact system contract: "stocks:live" topic and string tuple {"new_price", payload}
      Phoenix.PubSub.broadcast(
        StockFetcher.PubSub,
        "stocks:live",
        {"new_price", payload}
      )

      assert_push("new_price", ^payload)
    end

    test "handles multiple rapid PubSub ticks in order", %{socket: _socket} do
      ticks = [
        %{id: 1, ticker: "AAPL", price: 180.00},
        %{id: 2, ticker: "AAPL", price: 180.50},
        %{id: 3, ticker: "AAPL", price: 181.25}
      ]

      for tick <- ticks do
        Phoenix.PubSub.broadcast(
          StockFetcher.PubSub,
          "stocks:live",
          {"new_price", tick}
        )
      end

      # Asserts that WebSocket messages are pushed sequentially in FIFO order
      assert_push("new_price", %{id: 1, ticker: "AAPL", price: 180.00})
      assert_push("new_price", %{id: 2, ticker: "AAPL", price: 180.50})
      assert_push("new_price", %{id: 3, ticker: "AAPL", price: 181.25})
    end
  end
end
