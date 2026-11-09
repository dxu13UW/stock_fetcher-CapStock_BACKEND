defmodule StockFetcher.HealthTest do
  # async: false: the sampler owns named ETS tables.
  use ExUnit.Case, async: false

  alias StockFetcher.Health

  test "snapshot reports memory, processes and status without any other process" do
    snap = Health.snapshot()

    assert snap.status in ~w(ok tight critical)
    assert snap.beam.total_mb > 0
    assert snap.processes > 0 and snap.process_limit > snap.processes
    assert snap.uptime_s >= 0
    assert snap.lv_connections_per_ip_per_min == 1_000_000

    # /proc/meminfo exists on Linux (Fly, WSL); the page copes with nil elsewhere.
    if File.exists?("/proc/meminfo") do
      assert snap.vm.total_mb > 0
      assert snap.vm.available_mb <= snap.vm.total_mb
    end
  end

  test "history and peaks are empty, not an error, when the sampler isn't running" do
    assert Health.history() == []
    assert Health.peaks() == %{}
  end

  test "the sampler records samples into ETS, keeps the newest 120, and tracks peaks" do
    start_supervised!({Health, interval: 1})
    Process.sleep(200)

    history = Health.history()
    assert length(history) in 2..120
    assert [%{at: _, beam_mb: beam} | _] = history
    assert beam > 0
    assert %{max_beam_mb: %{value: _, at: _}} = Health.peaks()
  end
end
