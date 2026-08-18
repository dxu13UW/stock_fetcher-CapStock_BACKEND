defmodule StockFetcherWeb.StockChannel do
  @moduledoc """
  Phoenix Channel responsible for live real-time stock price streaming and historical data requests.

  Subscribes connected clients to either `"stocks:live"` or `"stocks:mock"` topics and forwards
  price updates broadcast over `Phoenix.PubSub` directly to connected WebSocket clients.
  """

  use Phoenix.Channel
  require Logger

  @cooldown_ms 500

  # Tell Phoenix to route "new_price" broadcasts through handle_out/3
  intercept ["new_price"]

  # Clause 1: Client explicitly joins "stocks:mock"
  @impl true
  def join("stocks:mock", _params, socket) do
    Logger.info("Client connected to MOCK stream route")
    {:ok, socket}
  end

  # Clause 2: Client explicitly joins "stocks:live"
  @impl true
  def join("stocks:live", _params, socket) do
    Logger.info("Client connected to LIVE stream route")
    {:ok, assign(socket, :last_historical_request_at, 0)}
  end

  # Catch-all clause for invalid subtopics
  @impl true
  def join("stocks:" <> invalid_topic, _params, _socket) do
    Logger.warning("Unauthorized channel join attempt on subtopic: stocks:#{invalid_topic}")
    {:error, %{reason: "unauthorized_topic"}}
  end

  @doc """
  Intercepts outbound `"new_price"` PubSub broadcasts before transmission.

  Logs structured payload details including the target socket transport PID,
  then pushes the price tick down the WebSocket connection to the client.
  """
  @impl true
  def handle_out("new_price", payload, socket) do
    Logger.info(
      "[StockChannel] Pushing live tick -> #{payload.ticker}: $#{payload.price} to socket #{inspect(socket.transport_pid)}"
    )

    push(socket, "new_price", payload)
    {:noreply, socket}
  end

  @doc """
  Handles client pushes for deeper historical trend data.
  Flattens historical records into a list so the React frontend
  can filter by the selected ticker.
  """
  @impl true
  def handle_in("request_historical", %{"limit" => _limit}, socket) do
    now = System.monotonic_time(:millisecond)
    last_request_at = socket.assigns[:last_historical_request_at] || 0
    time_elapsed = now - last_request_at

    if time_elapsed < @cooldown_ms do
      retry_after_ms = @cooldown_ms - time_elapsed

      {:reply, {:error, %{reason: "rate_limited", retry_after_ms: retry_after_ms}}, socket}
    else
      socket = assign(socket, :last_historical_request_at, now)

      data =
        get_watchlist_data(socket.topic)
        |> Map.values()
        |> List.flatten()

      {:reply, {:ok, %{data: data}}, socket}
    end
  end

  @doc """
  Handles incoming price update messages broadcast over PubSub.
  """
  @impl true
  def handle_info({"new_price", payload}, socket) do
    Logger.info(
      "[StockChannel] Pushing live tick -> #{payload.ticker}: $#{payload.price} to socket #{inspect(socket.transport_pid)}"
    )

    push(socket, "new_price", payload)
    {:noreply, socket}
  end

  @doc """
  Invoked when the socket connection is closed or the channel process terminates.
  """
  @impl true
  def terminate(reason, socket) do
    Logger.info("Client disconnected from '#{socket.topic}'. Reason: #{inspect(reason)}")
    :ok
  end

  # --- Internal Helpers ---

  # Pattern matches when socket.topic is "stocks:mock"
  defp get_watchlist_data("stocks:mock") do
    StockFetcher.Mock.Hydration.hydrate_watchlist()
  end

  # Pattern matches for "stocks:live" with an off-hours empty database fallback
  defp get_watchlist_data(_live_topic) do
    case StockFetcher.get_hydrated_watchlist() do
      map when map_size(map) == 0 -> StockFetcher.Mock.Hydration.hydrate_watchlist()
      hydrated_map -> hydrated_map
    end
  end
end
