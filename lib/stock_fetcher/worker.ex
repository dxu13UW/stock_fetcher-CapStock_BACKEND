# See https://elixir.hexdocs.pm/GenServer.html for documentations of funtionalities and callback functions.
defmodule StockFetcher.Worker do
  @moduledoc """
  Acts as a background manager process built on `GenServer` to automate scheduled stock market data polling.
  It uses `Task.async_stream` to make concurrent HTTP requests to the external Finnhub API, handles rate limits
  and network failures gracefully, and passes successfully fetched ticker prices to `StockFetcher.save_price/2`
  """
  use GenServer

  # 5 workers running concurrently
  @stocks ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]
  # Poll every 15 seconds (well within Finnhub's limits!)
  @polling_interval 15_000

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # --- Server Callbacks ---

  # Callback function init/1 see doc
  @impl true
  def init(opts) do
    schedule_timer = Keyword.get(opts, :schedule_timer, true)
    test_pid = Keyword.get(opts, :test_pid)

    if schedule_timer do
      schedule_next_poll()
    end

    {:ok, %{schedule_timer: schedule_timer, test_pid: test_pid}}
  end

  # Callback function handle_info/2 see doc
  @impl true
  def handle_info(:poll_market, state) do
    IO.puts("[Worker] Running parallel Finnhub fetch and writing to SQLite...")

    @stocks
    # config each worker
    |> Task.async_stream(&StockFetcher.fetch_stock_data/1, max_concurrency: 5, timeout: 5000)
    |> Enum.each(fn
      {:ok, {:ok, ticker, price}} ->
        StockFetcher.save_price(ticker, price)

      {:ok, {:error, ticker, reason}} ->
        IO.puts("[Error] Failed to fetch #{ticker}: #{reason}")

      {:error, reason} ->
        IO.puts("[Error] Process crashed: #{inspect(reason)}")
    end)

    # For ExUnit testing
    if state.test_pid do
      send(state.test_pid, :poll_complete)
    end

    if state.schedule_timer do
      schedule_next_poll()
    end

    {:noreply, state}
  end

  # --- Helper Functions ---

  defp schedule_next_poll do
    Process.send_after(self(), :poll_market, @polling_interval)
  end
end
