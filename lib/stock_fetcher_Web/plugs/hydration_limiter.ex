defmodule StockFetcherWeb.Plugs.HydrationLimiter do
  @behaviour Plug
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @limit 20
  @scale_ms 60_000

  @impl true
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @limit),
      scale_ms: Keyword.get(opts, :scale_ms, @scale_ms),
      key_prefix: Keyword.get(opts, :key_prefix, "hydrate"),
      error: Keyword.get(opts, :error, "Hydration rate limit exceeded."),
      message:
        Keyword.get(
          opts,
          :message,
          "Please stop refreshing the page. Data is streamed to client via active Websocket."
        )
    }
  end

  @impl true
  def call(
        conn,
        %{
          limit: limit,
          scale_ms: scale_ms,
          key_prefix: prefix,
          error: err,
          message: msg
        }
      ) do
    client_ip = extract_ip(conn)
    key = "#{prefix}:#{client_ip}"

    case Hammer.check_rate(key, scale_ms, limit) do
      {:allow, count} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(max(limit - count, 0)))

      {:deny, retry_after} ->
        retry_seconds = max(1, System.convert_time_unit(retry_after, :millisecond, :second))

        conn
        |> put_resp_header("retry-after", to_string(retry_seconds))
        |> put_status(:too_many_requests)
        |> json(%{
          error: err,
          message: msg,
          retry_after: retry_seconds
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
