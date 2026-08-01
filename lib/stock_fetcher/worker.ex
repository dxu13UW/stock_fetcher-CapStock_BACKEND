# See https://elixir.hexdocs.pm/GenServer.html for documentations of funtionalities and callback functions.
defmodule StockFetcher.Worker do
  @moduledoc """
  Acts as a background manager process built on `GenServer` to automate scheduled stock market data polling.
  It uses `Task.async_stream` to make concurrent HTTP requests to the external Finnhub API, handles rate limits
  and network failures gracefully, and passes successfully fetched ticker prices to `StockFetcher.save_price/2`
  It checks standard US market hours before fetching; if open, it polls on a standard interval, and if closed,
  it hibernates until the next market opening bell.
  """
  use GenServer
  require Logger
  alias StockFetcher.MarketHours

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
    # Default to real clock, but allows injecting fixed DateTime in tests
    now_fn = Keyword.get(opts, :now_fn, &DateTime.utc_now/0)

    if schedule_timer do
      schedule_next_poll()
    end

    {:ok, %{schedule_timer: schedule_timer, test_pid: test_pid, now_fn: now_fn}}
  end

  # Callback function handle_info/2 see doc
  @impl true
  def handle_info(:poll_market, state) do
    current_time = state.now_fn.()

    next_interval =
      if MarketHours.market_open?(current_time) do
        Logger.info("[Worker] Market is OPEN. Running parallel Finnhub fetch...")

        @stocks
        |> Task.async_stream(&StockFetcher.fetch_stock_data/1, max_concurrency: 5, timeout: 5000)
        |> Enum.each(&handle_fetch_result/1)

        @polling_interval
      else
        ms_until_open = MarketHours.ms_until_next_open(current_time)
        hours_until_open = Float.round(ms_until_open / 3_600_000, 2)

        Logger.info(
          "[Worker] Market is CLOSED. Hibernating until next opening bell in #{hours_until_open} hours."
        )

        ms_until_open
      end

    # For ExUnit testing notification
    if state.test_pid, do: send(state.test_pid, {:poll_complete, next_interval})

    if state.schedule_timer do
      schedule_next_poll(next_interval)
    end

    {:noreply, state}
  end

  # --- Helper Functions ---

  defp schedule_next_poll(interval \\ @polling_interval) do
    Process.send_after(self(), :poll_market, interval)
  end

  # Processes the result of an asynchronous fetch task emitted by `Task.async_stream/3`.
  #
  # ## Behavior
  # * `{:ok, {:ok, ticker, price}}`     — Saves the valid stock price to SQLite via
  # * `{:ok, {:ok, ticker, price}}`     — Saves to SQLite and broadcasts via PubSub.
  # * `{:ok, {:error, ticker, reason}}` — Logs fetch/rate-limit errors.
  # * `{:error, reason}`                — Logs task timeout or process crash.
  defp handle_fetch_result({:ok, {:ok, ticker, price}}) do
    case StockFetcher.save_price(ticker, price) do
      {:ok, stock_price} ->
        Phoenix.PubSub.broadcast(
          StockFetcher.PubSub,
          "stocks:live",
          {"new_price",
           %{
             id: stock_price.id,
             ticker: stock_price.ticker,
             price: stock_price.price,
             timestamp: stock_price.inserted_at
           }}
        )

      {:error, changeset} ->
        IO.puts("[Error] Failed to save #{ticker} to SQLite: #{inspect(changeset.errors)}")
    end
  end

  defp handle_fetch_result({:ok, {:error, ticker, reason}}) do
    IO.puts("[Error] Failed to fetch #{ticker}: #{reason}")
  end

  defp handle_fetch_result({:error, reason}) do
    IO.puts("[Error] Task process crashed: #{inspect(reason)}")
  end
end
