defmodule StockFetcher.Mock.Streamer do
  @moduledoc """
  A GenServer that simulates a live market ticker stream over Phoenix.PubSub.

  Two instances run (2026-11-07): the original one on "stocks:mock" for the 5 tickers the
  React SPA knows, and `StockFetcher.Mock.Streamer.Extra` on "stocks:mock:extra" for the other
  45 (`StockFetcher.Tickers`). Separate topics keep the React SPA at its 5 tickers. The extra
  one moves several tickers per tick, so each of its 45 still changes every few seconds.

  Options: `:name`, `:enabled`, `:topic` (default "stocks:mock"), `:prices` (ticker => starting
  price, default the original 5), `:per_tick` (tickers moved per tick, default 1).
  """

  use GenServer
  require Logger

  @pubsub_topic "stocks:mock"
  @update_interval 1_500

  @min_price 1.00
  @max_price 5000.00

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

    {:ok,
     %{
       prices:
         Keyword.get_lazy(opts, :prices, fn -> StockFetcher.Tickers.mock_prices(:finnhub) end),
       topic: Keyword.get(opts, :topic, @pubsub_topic),
       per_tick: Keyword.get(opts, :per_tick, 1),
       enabled: enabled
     }}
  end

  @doc """
  The latest price of every ticker, as broadcast payloads (`%{ticker, price, timestamp}`), so a
  page that opens between ticks can show prices at once instead of waiting for each one.
  Returns `[]` if the streamer isn't running.
  """
  def current_prices(name \\ __MODULE__) do
    if GenServer.whereis(name), do: GenServer.call(name, :current_prices), else: []
  end

  @impl true
  def handle_call(:current_prices, _from, state) do
    now = DateTime.utc_now()
    list = Enum.map(state.prices, fn {t, p} -> %{ticker: t, price: p, timestamp: now} end)
    {:reply, list, state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_prices =
      state.prices
      |> Enum.take_random(state.per_tick)
      |> Enum.reduce(state.prices, fn {ticker, price}, acc ->
        Map.put(acc, ticker, move(ticker, price, state.topic))
      end)

    if state.enabled do
      schedule_next_tick()
    end

    {:noreply, %{state | prices: new_prices}}
  end

  # One random step for one ticker, broadcast on the streamer's topic. Returns the new price.
  # The step scales with the price (about ±0.4%), so a $10 stock and an $800 one both move
  # visibly; the original 5 keep their old fixed ±$0.75 step.
  defp move(ticker, current_price, topic) do
    delta =
      if topic == @pubsub_topic,
        do: (:rand.uniform() - 0.5) * 1.50,
        else: (:rand.uniform() - 0.5) * current_price * 0.008

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

    Phoenix.PubSub.broadcast(StockFetcher.PubSub, topic, {"new_price", payload})
    new_price
  end

  defp schedule_next_tick do
    Process.send_after(self(), :tick, @update_interval)
  end
end
