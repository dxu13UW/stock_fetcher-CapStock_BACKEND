defmodule StockFetcher.Health do
  @moduledoc """
  Server health for the `/health` page (2026-11-08): memory, processes, open tabs, uptime, and
  a 10-minute history.

  Built to answer even when the server is struggling:
    * `snapshot/0` uses only cheap VM built-ins, one small file read (`/proc/meminfo`) and a
      file stat. It never calls another process, so a busy GenServer can't make it wait, and it
      never touches the database.
    * Open tabs = how many tab processes `SessionJanitor` monitors, read with `Process.info/2`,
      which doesn't need the janitor's cooperation.
    * This GenServer samples every 5 s into ETS. Readers go straight to the table, so a slow
      sampler only means a stale chart, never a slow page.

  Why VM memory and not just BEAM memory: the 256 MB Fly machine was OOM-killed twice
  (2026-11-08/09). The kernel kills on the *machine's* available memory, which includes more
  than the BEAM's own count, so `/proc/meminfo`'s MemAvailable is the number to watch.
  """
  use GenServer

  @samples :capstock_health_samples
  @peaks :capstock_health_peaks
  @keep 120
  @default_interval 5_000

  # Below these, the page says "tight" / "critical". The 2026-11-09 OOM kill happened with the
  # BEAM at ~190 MB resident on a 256 MB machine.
  @tight_mb 64
  @critical_mb 32

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    :ets.new(@samples, [:ordered_set, :named_table, :protected, read_concurrency: true])
    :ets.new(@peaks, [:set, :named_table, :protected, read_concurrency: true])
    interval = Keyword.get(opts, :interval, @default_interval)
    send(self(), :sample)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:sample, state) do
    record(snapshot())
    Process.send_after(self(), :sample, state.interval)
    {:noreply, state}
  end

  defp record(snap) do
    now = System.system_time(:millisecond)

    sample = %{
      at: now,
      vm_available_mb: snap.vm && snap.vm.available_mb,
      beam_mb: snap.beam.total_mb,
      open_tabs: snap.open_tabs
    }

    :ets.insert(@samples, {now, sample})
    if :ets.info(@samples, :size) > @keep, do: :ets.delete(@samples, :ets.first(@samples))

    peak(:max_beam_mb, sample.beam_mb, now, &>/2)
    peak(:min_vm_available_mb, sample.vm_available_mb, now, &</2)
    peak(:max_open_tabs, sample.open_tabs, now, &>/2)
  end

  defp peak(_key, nil, _now, _better?), do: :ok

  defp peak(key, value, now, better?) do
    case :ets.lookup(@peaks, key) do
      [{^key, %{value: old}}] -> if better?.(value, old), do: put_peak(key, value, now)
      [] -> put_peak(key, value, now)
    end
  end

  defp put_peak(key, value, now), do: :ets.insert(@peaks, {key, %{value: value, at: now}})

  @doc "The last 10 minutes of samples, oldest first (empty if the sampler isn't running)."
  def history do
    @samples |> :ets.tab2list() |> Enum.map(&elem(&1, 1))
  rescue
    ArgumentError -> []
  end

  @doc "Peaks since boot: highest BEAM memory, lowest available VM memory, most open tabs."
  def peaks do
    @peaks |> :ets.tab2list() |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  @doc "Current health. Cheap and self-contained; see the moduledoc."
  def snapshot do
    vm = vm_memory()
    beam = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      status: status(vm, beam[:total]),
      uptime_s: div(uptime_ms, 1000),
      vm: vm,
      beam: %{
        total_mb: mb(beam[:total]),
        processes_mb: mb(beam[:processes]),
        binary_mb: mb(beam[:binary]),
        ets_mb: mb(beam[:ets]),
        code_mb: mb(beam[:code])
      },
      processes: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      run_queue: :erlang.statistics(:total_run_queue_lengths_all),
      schedulers: :erlang.system_info(:schedulers_online),
      open_tabs: open_tabs(),
      db_mb: db_mb(),
      lv_connections_per_ip_per_min:
        Application.get_env(:stock_fetcher, :lv_connections_per_minute, 200)
    }
  end

  defp status(nil, _beam_total), do: "ok"

  defp status(%{available_mb: available}, _beam_total) do
    cond do
      available < @critical_mb -> "critical"
      available < @tight_mb -> "tight"
      true -> "ok"
    end
  end

  # The machine's memory, as the kernel's OOM killer sees it. nil off Linux.
  defp vm_memory do
    with {:ok, text} <- File.read("/proc/meminfo"),
         total when is_integer(total) <- meminfo_kb(text, "MemTotal"),
         available when is_integer(available) <- meminfo_kb(text, "MemAvailable") do
      %{
        total_mb: mb(total * 1024),
        available_mb: mb(available * 1024),
        used_pct: round((total - available) * 100 / total)
      }
    else
      _ -> nil
    end
  end

  defp meminfo_kb(text, key) do
    case Regex.run(~r/^#{key}:\s+(\d+) kB$/m, text) do
      [_, kb] -> String.to_integer(kb)
      _ -> nil
    end
  end

  defp open_tabs do
    with pid when is_pid(pid) <- Process.whereis(StockFetcher.Trading.SessionJanitor),
         {:monitors, monitors} <- Process.info(pid, :monitors) do
      length(monitors)
    else
      _ -> nil
    end
  end

  defp db_mb do
    path = Application.get_env(:stock_fetcher, StockFetcher.Repo, [])[:database]

    sizes =
      for file <- [path, "#{path}-wal"],
          is_binary(path),
          {:ok, %{size: size}} <- [File.stat(file)],
          do: size

    if sizes == [], do: nil, else: mb(Enum.sum(sizes))
  end

  defp mb(bytes), do: Float.round(bytes / 1_048_576, 1)
end
