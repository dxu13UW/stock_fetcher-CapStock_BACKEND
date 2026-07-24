defmodule StockFetcher.Pruner do
  @moduledoc """
  A background GenServer worker that periodically cleans up stock price records
  based on retention age (7 days) and maximum database size (2MB).
  """
  use GenServer
  require Logger

  # Default cleanup interval: 4 hours (in milliseconds)
  @default_interval :timer.hours(4)
  # Default file size before auto cleanup: 2 MB
  @default_max_bytes 2_000_000

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    days_to_keep = Keyword.get(opts, :days_to_keep, 7)
    interval = Keyword.get(opts, :interval, @default_interval)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    test_pid = Keyword.get(opts, :test_pid)

    if Keyword.get(opts, :schedule_timer, true) do
      schedule_prune(interval)
    end

    Logger.info("[Pruner] Started automatic database pruner worker...")

    {:ok,
     %{
       interval: interval,
       days_to_keep: days_to_keep,
       max_bytes: max_bytes,
       test_pid: test_pid
     }}
  end

  @impl true
  def handle_info(:prune, state) do
    Logger.info("[Pruner] Running scheduled cleanup...")

    StockFetcher.Repo.transaction(fn ->
      # Prune by Age
      {age_count, _} = StockFetcher.prune_old_prices(state.days_to_keep)

      if age_count > 0 do
        Logger.info(
          "[Pruner] Deleted #{age_count} records older than #{state.days_to_keep} days."
        )
      end

      # Prune by Database Size Threshold
      current_size = StockFetcher.get_db_size()

      if current_size > state.max_bytes do
        Logger.warning(
          "[Pruner] DB size (#{current_size} bytes) exceeds limit (#{state.max_bytes} bytes). Pruning oldest 25%..."
        )

        {percent_count, _} = StockFetcher.prune_oldest_percent(25)
        Logger.info("[Pruner] Deleted #{percent_count} records due to size threshold.")
      end
    end)

    # For ExUnit testing
    if state.test_pid do
      send(state.test_pid, :prune_complete)
    end

    schedule_prune(state.interval)
    {:noreply, state}
  end

  # --- Helper Functions ---

  defp schedule_prune(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
