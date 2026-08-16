defmodule StockFetcherWeb.Plugs.HydrationLimiter do
  @behaviour Plug
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @limit 20
  @scale_ms 60_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    client_ip = extract_ip(conn)
    key = "hydrate:#{client_ip}"

    case Hammer.check_rate(key, @scale_ms, @limit) do
      {:allow, count} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(@limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(max(@limit - count, 0)))
        |> put_resp_header("cache-control", "public, max-age=10")

      {:deny, _retry_after} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> put_status(:too_many_requests)
        |> json(%{
          error: "Hydration rate limit exceeded.",
          message: "Please rely on the active WebSocket stream for live price updates."
        })
        |> halt()
    end
  end

  defp extract_ip(conn) do
    cond do
      ip = get_first_header(conn, "fly-client-ip") ->
        ip

      ip = get_first_header(conn, "x-forwarded-for") ->
        ip |> String.split(",") |> List.first() |> String.trim()

      true ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp get_first_header(conn, header_name) do
    case Plug.Conn.get_req_header(conn, header_name) do
      [val | _] -> val
      [] -> nil
    end
  end
end
