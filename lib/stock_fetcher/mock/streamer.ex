defmodule StockFetcher.Mock.Streamer do
  @moduledoc """
  A GenServer that simulates a live market ticker stream over Phoenix.PubSub.
  """

  use GenServer
  require Logger

  @pubsub_topic "stocks:mock"
  @update_interval 1_500

  @min_price 1.00
  @max_price 1000.00

  @initial_prices %{
    "AAPL" => 180.00,
    "AMZN" => 175.00,
    "GOOGL" => 150.00,
    "MSFT" => 400.00,
    "TSLA" => 220.00
  }

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)

    if enabled do
      schedule_next_tick()
    end

    {:ok, %{prices: @initial_prices, enabled: enabled}}
  end

  @impl true
  def handle_info(:tick, state) do
    {ticker, current_price} = Enum.random(state.prices)

    delta = (:rand.uniform() - 0.5) * 1.50

    # Clamps calculated price to [@min_price, @max_price] via pipe chain
    new_price =
      (current_price + delta)
      |> max(@min_price)
      |> min(@max_price)
      |> Float.round(2)

    payload = %{
      id: System.unique_integer([:positive]),
      ticker: ticker,
      price: new_price,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(StockFetcher.PubSub, @pubsub_topic, {"new_price", payload})

    new_prices = Map.put(state.prices, ticker, new_price)

    if state.enabled do
      schedule_next_tick()
    end

    {:noreply, %{state | prices: new_prices}}
  end

  defp schedule_next_tick do
    Process.send_after(self(), :tick, @update_interval)
  end
end
