defmodule StockFetcherWeb.TelemetryHandler do
  @moduledoc """
  Translates domain telemetry events into real-time Phoenix.PubSub broadcasts
  for WebSocket subscribers.
  """
  require Logger

  @pubsub_topic "stocks:live"

  @doc """
  Attaches telemetry handlers to the Erlang telemetry event pipeline at boot.
  """
  def attach do
    events = [
      [:stock_fetcher, :stock_price, :saved]
    ]

    :telemetry.attach_many(
      "stock-price-websocket-bridge",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Callback function invoked by :telemetry when [:stock_fetcher, :stock_price, :saved] is emitted.
  """
  def handle_event(
        [:stock_fetcher, :stock_price, :saved],
        _measurements,
        %{stock_price: stock_price},
        _config
      ) do
    payload = %{
      id: stock_price.id,
      ticker: stock_price.ticker,
      price: normalize_float(stock_price.price),
      timestamp: stock_price.inserted_at
    }

    Phoenix.PubSub.broadcast(StockFetcher.PubSub, @pubsub_topic, {"new_price", payload})
  end

  # --- Internal Helpers ---

  defp normalize_float(%Decimal{} = dec), do: Decimal.to_float(dec)
  defp normalize_float(val) when is_float(val), do: val
  defp normalize_float(val) when is_integer(val), do: val * 1.0
end
