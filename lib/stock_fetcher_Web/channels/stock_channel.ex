defmodule StockFetcherWeb.StockChannel do
  @moduledoc """
  Phoenix Channel responsible purely for live real-time stock price streaming.

  Subscribes connected clients to the `"stocks:live"` topic and forwards
  live price updates broadcast by `Phoenix.PubSub` directly over WebSockets.
  """

  use Phoenix.Channel
  require Logger

  # Clause 1: Client explicitly joins "stocks:mock"
  @impl true
  def join("stocks:mock", _params, socket) do
    Logger.info("Client connected to MOCK stream route")
    {:ok, socket}
  end

  # Clause 2: Client explicitly joins "stocks:live"  @impl true
  def join("stocks:live", _params, socket) do
    Logger.info("Client connected to LIVE stream route")
    {:ok, socket}
  end

  # Catch-all clause for invalid subtopics
  @impl true
  def join("stocks:" <> _invalid, _params, _socket) do
    {:error, %{reason: "unauthorized_topic"}}
  end

  @doc """
  Handles process messages emitted over `Phoenix.PubSub` matching `{"new_price", stock_data}`.
  Pushes live price ticks down the WebSocket connection as `"new_price"` events.
  """
  @impl true
  def handle_info({"new_price", stock_data}, socket) do
    push(socket, "new_price", stock_data)
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
end
