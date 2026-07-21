# See https://elixir.hexdocs.pm/GenServer.html for documentations of funtionalities and callback functions.
defmodule StockFetcher.Worker do
  use GenServer

  # 5 workers running concurrently
  @stocks ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]
  # Poll every 15 seconds (well within Finnhub's limits!)
  @polling_interval 15_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callback function init/1 see doc
  @impl true
  def init(state) do
    IO.puts("[Worker] Starting automatic database stock-poller...")
    schedule_next_poll()
    {:ok, state}
  end

  # Callback function handle_info/2 see doc
  @impl true
  def handle_info(:poll_market, state) do
    IO.puts("[Worker] Running parallel Finnhub fetch and writing to SQLite...")

    @stocks
    # config each worker
    |> Task.async_stream(&fetch_stock_data/1, max_concurrency: 5, timeout: 5000)
    |> Enum.each(fn
      {:ok, {:ok, ticker, price}} ->
        StockFetcher.save_price(ticker, price)

      {:ok, {:error, ticker, reason}} ->
        IO.puts("[Error] Failed to fetch #{ticker}: #{reason}")

      {:error, reason} ->
        IO.puts("[Error] Process crashed: #{inspect(reason)}")
    end)

    schedule_next_poll()
    {:noreply, state}
  end

  # --- Helper Functions ---

  defp schedule_next_poll do
    Process.send_after(self(), :poll_market, @polling_interval)
  end

  defp fetch_stock_data(ticker) do
    token = System.fetch_env!("FINNHUB_API_TOKEN")

    url = "https://finnhub.io/api/v1/quote?symbol=#{ticker}&token=#{token}"

    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: %{"c" => price}}} when price > 0 ->
        {:ok, ticker, price}

      {:ok, %Req.Response{status: 401}} ->
        {:error, ticker, "Invalid API Key"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, ticker, "Rate Limit Reached"}

      {:ok, %Req.Response{status: status}} ->
        {:error, ticker, "HTTP Error #{status}"}

      {:error, exception} ->
        {:error, ticker, "Network Failure: #{inspect(exception)}"}
    end
  end
end
