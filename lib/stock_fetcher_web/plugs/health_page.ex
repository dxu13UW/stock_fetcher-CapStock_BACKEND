defmodule StockFetcherWeb.Plugs.HealthPage do
  @moduledoc """
  `GET /health`: a self-refreshing page of server health; `/health?format=json` (or an
  `Accept: application/json` request) returns the same data as JSON. 2026-11-08.

  Kept as cheap as possible so it still loads when the server is under strain:
    * the first plug in the endpoint, so a request skips static files, CORS, body parsing,
      sessions, the router and logging;
    * no LiveView (a page process would count against the very limits it reports on), no
      database, no calls to other processes (see `StockFetcher.Health`);
    * one small HTML response with inline CSS and SVG: no JS or CSS files to fetch;
    * not rate-limited: it costs about as much as a 404.

  The one thing it can't get past is Fly's proxy cap (fly.toml: 250 connections). That cap is
  what keeps memory safe, so if it's full, this waits like any other request.
  """
  @behaviour Plug
  import Plug.Conn

  alias StockFetcher.Health

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", request_path: "/health"} = conn, _opts) do
    conn = fetch_query_params(conn)
    snap = Health.snapshot()
    data = Map.merge(snap, %{history: Health.history(), peaks: Health.peaks()})

    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-robots-tag", "noindex")

    if json?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(data))
      |> halt()
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, page(data))
      |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp json?(conn) do
    conn.query_params["format"] == "json" or
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json"))
  end

  # --- HTML ---

  defp page(d) do
    """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="refresh" content="5">
    <title>Capstock health</title>
    <style>
    :root{--bg:#fff;--fg:#18181b;--muted:#71717a;--card:#f4f4f5;--line:#e4e4e7;--ok:#059669;--tight:#d97706;--critical:#e11d48;--chart:#0284c7}
    @media (prefers-color-scheme:dark){:root{--bg:#09090b;--fg:#f4f4f5;--muted:#a1a1aa;--card:#18181b;--line:#27272a;--chart:#38bdf8}}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,sans-serif}
    main{max-width:56rem;margin:0 auto;padding:24px 16px}h1{font-size:1.4rem;margin:0}
    .sub{color:var(--muted);font-size:.85rem;margin:.2rem 0 1.2rem}
    .badge{display:inline-block;padding:.1rem .6rem;border-radius:999px;color:#fff;font-weight:600;font-size:.85rem;vertical-align:middle;margin-left:.4rem}
    .ok{background:var(--ok)}.tight{background:var(--tight)}.critical{background:var(--critical)}
    .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(15rem,1fr));gap:12px}
    .card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
    .label{color:var(--muted);font-size:.75rem;text-transform:uppercase;letter-spacing:.04em}
    .big{font-size:1.5rem;font-weight:650;font-variant-numeric:tabular-nums}
    .small{color:var(--muted);font-size:.8rem;font-variant-numeric:tabular-nums}
    svg{width:100%;height:56px;display:block;margin-top:6px}
    footer{color:var(--muted);font-size:.8rem;margin-top:1.2rem}
    a{color:var(--chart)}
    </style></head><body><main>
    <h1>Capstock health<span class="badge #{d.status}">#{d.status}</span></h1>
    <p class="sub">Refreshes every 5 s · up #{duration(d.uptime_s)} · <a href="/health?format=json">JSON</a></p>
    <div class="grid">
    #{vm_card(d)}
    #{card("Open tabs", fmt(d.open_tabs), "most since boot: #{peak(d.peaks, :max_open_tabs, "")}", spark(d.history, :open_tabs))}
    #{card("App memory (BEAM)", "#{d.beam.total_mb} MB", "processes #{d.beam.processes_mb} · binary #{d.beam.binary_mb} · ETS #{d.beam.ets_mb} · code #{d.beam.code_mb} MB<br>highest since boot: #{peak(d.peaks, :max_beam_mb, " MB")}", spark(d.history, :beam_mb))}
    #{card("Processes", "#{d.processes}", "limit #{d.process_limit} · run queue #{d.run_queue} on #{d.schedulers} scheduler(s)", "")}
    #{card("Database", if(d.db_mb, do: "#{d.db_mb} MB", else: "–"), "SQLite on the Fly volume", "")}
    #{card("Limits", "#{d.lv_connections_per_ip_per_min}/min", "new LiveView tabs per IP<br>Fly proxy: 200 soft / 250 hard connections", "")}
    </div>
    <footer>Charts: last #{length(d.history)} samples, one every 5 s. "tight" below 64 MB available, "critical" below 32 MB: the 256 MB machine was OOM-killed on 2026-11-09.</footer>
    </main></body></html>
    """
  end

  defp vm_card(%{vm: nil} = d),
    do:
      card("Machine memory", "–", "not available on this OS", spark(d.history, :vm_available_mb))

  defp vm_card(%{vm: vm} = d) do
    card(
      "Machine memory available",
      "#{vm.available_mb} MB",
      "of #{vm.total_mb} MB (#{vm.used_pct}% used)<br>lowest since boot: #{peak(d.peaks, :min_vm_available_mb, " MB")}",
      spark(d.history, :vm_available_mb)
    )
  end

  defp card(label, big, small, chart) do
    ~s(<div class="card"><div class="label">#{label}</div><div class="big">#{big}</div><div class="small">#{small}</div>#{chart}</div>)
  end

  defp peak(peaks, key, unit) do
    case peaks[key] do
      %{value: value, at: at} -> "#{value}#{unit} at #{clock(at)} UTC"
      _ -> "–"
    end
  end

  # A line chart of one field over the samples, scaled to its own min and max.
  defp spark(history, field) do
    values = for s <- history, v = s[field], is_number(v), do: v

    if length(values) < 2 do
      ""
    else
      {lo, hi} = Enum.min_max(values)
      span = if hi == lo, do: 1, else: hi - lo
      step = 300 / (length(values) - 1)

      points =
        values
        |> Enum.with_index()
        |> Enum.map_join(" ", fn {v, i} ->
          "#{Float.round(i * step, 1)},#{Float.round(52 - (v - lo) / span * 48, 1)}"
        end)

      ~s(<svg viewBox="0 0 300 56" preserveAspectRatio="none" aria-hidden="true"><polyline points="#{points}" fill="none" stroke="var\(--chart\)" stroke-width="2" vector-effect="non-scaling-stroke"/></svg><div class="small">#{lo} – #{hi}</div>)
    end
  end

  defp fmt(nil), do: "–"
  defp fmt(n), do: to_string(n)

  defp duration(s) when s < 3600, do: "#{div(s, 60)} min"
  defp duration(s), do: "#{div(s, 3600)} h #{div(rem(s, 3600), 60)} min"

  defp clock(ms),
    do:
      ms
      |> DateTime.from_unix!(:millisecond)
      |> DateTime.to_time()
      |> Time.truncate(:second)
      |> to_string()
end
