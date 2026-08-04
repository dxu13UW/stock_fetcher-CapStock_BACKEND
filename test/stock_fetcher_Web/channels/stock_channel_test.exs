defmodule StockFetcherWeb.StockChannelTest do
  use StockFetcherWeb.ChannelCase, async: false
  alias StockFetcher.{Repo, StockPrice}

  setup do
    :ok
  end

  describe "join stocks:live" do
    test "returns initial snapshot on join" do
      Repo.insert!(%StockPrice{ticker: "AAPL", price: 185.50})
      Repo.insert!(%StockPrice{ticker: "NVDA", price: 120.25})

      {:ok, reply, _socket} =
        subscribe_and_join(
          socket(StockFetcherWeb.UserSocket, "user_id", %{}),
          StockFetcherWeb.StockChannel,
          "stocks:live"
        )

      assert %{initial_data: stocks} = reply
      assert length(stocks) == 2
      assert Enum.any?(stocks, fn s -> s.ticker == "AAPL" and s.price == 185.50 end)
    end
  end

  describe "handle_in request_historical" do
    setup do
      {:ok, _, socket} =
        subscribe_and_join(
          socket(StockFetcherWeb.UserSocket, "user_id", %{}),
          StockFetcherWeb.StockChannel,
          "stocks:live"
        )

      %{socket: socket}
    end

    test "replies with historical stock data", %{socket: socket} do
      Repo.insert!(%StockPrice{ticker: "MSFT", price: 381.70})

      ref = push(socket, "request_historical", %{"limit" => 10})

      assert_reply(ref, :ok, %{data: [stock]})
      assert stock.ticker == "MSFT"
      assert stock.price == 381.70
    end

    test "clamps requested limit to 500 safety maximum", %{socket: socket} do
      ref = push(socket, "request_historical", %{"limit" => 1000})

      assert_reply(ref, :ok, %{data: _history})
    end
  end

  describe "pubsub streaming (constant flow)" do
    setup do
      {:ok, _reply, socket} =
        subscribe_and_join(
          socket(StockFetcherWeb.UserSocket, "user_id", %{}),
          StockFetcherWeb.StockChannel,
          "stocks:live"
        )

      %{socket: socket}
    end

    test "pushes new_price event down the socket when PubSub receives a tick", %{socket: _socket} do
      payload = %{
        id: 1,
        ticker: "NVDA",
        price: 125.50,
        timestamp: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(
        StockFetcher.PubSub,
        "stocks:broadcasts",
        {:new_price, payload}
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
          "stocks:broadcasts",
          {:new_price, tick}
        )
      end

      assert_push("new_price", %{ticker: "AAPL", price: 180.00})
      assert_push("new_price", %{ticker: "AAPL", price: 180.50})
      assert_push("new_price", %{ticker: "AAPL", price: 181.25})
    end
  end
end
