defmodule StockFetcher.OrderWatcher do
  @moduledoc """
  Fills resting orders (step G: entries, stop-losses, take-profits) from a price stream. One instance per source:
  `source: :live` listens to "stocks:live" (Finnhub) and "stocks:extra" (Alpaca), `source: :mock`
  to "stocks:mock" and "stocks:mock:extra". A mock tick therefore can never reach a live order,
  even though both streams use the same tickers.

  Why a supervised process and not `PricesLive`: a LiveView lives as long as its tab. A
  stop-loss has to work while John isn't looking.

  It keeps no copy of the orders. On every tick it asks the DB for the open orders on that
  ticker, so the DB is the only source of truth: a crash or restart loses nothing, and new or
  cancelled orders need no message to reach it. The cost is one indexed query per tick
  (live: 5 per 15 s; mock: 1 per 1.5 s), which SQLite answers in well under a millisecond.

  After each fill or rejection it broadcasts `{:pending_order_event, kind, text}` on
  `Trading.portfolio_topic/1`, so an open `PricesLive` can refresh and say what happened.
  """
  use GenServer
  require Logger

  alias StockFetcher.Trading
  alias StockFetcher.Trading.PendingOrder

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :source)}, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Options: `:source` (`:live` | `:mock`, required), `:topic` (one topic instead of the source's
  defaults; tests pass their own), `:name`.
  """
  def start_link(opts) do
    source = Keyword.fetch!(opts, :source)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, name(source)))
  end

  def name(:live), do: __MODULE__.Live
  def name(:mock), do: __MODULE__.Mock

  @impl true
  def init(opts) do
    source = Keyword.fetch!(opts, :source)
    topics = if topic = opts[:topic], do: [topic], else: default_topics(source)
    Enum.each(topics, &(:ok = Phoenix.PubSub.subscribe(StockFetcher.PubSub, &1)))

    # Stored as a string because that's how pending_orders.source is saved.
    {:ok, %{source: Atom.to_string(source)}}
  end

  @impl true
  def handle_info({"new_price", %{ticker: ticker, price: price}}, state) do
    cents = price_cents(price)
    orders = Trading.list_open_orders(state.source, ticker)

    Enum.each(orders, fn order ->
      case Trading.fill_rule(order, cents) do
        {:fill, fill_cents} -> fill(order, fill_cents)
        :wait -> :ok
      end
    end)

    {:noreply, state}
  end

  # Anything else on the topic is ignored rather than crashing the watcher.
  def handle_info(_message, state), do: {:noreply, state}

  # --- Helpers for handle_info ---

  # Display and comparison only; Trading converts exactly when it fills.
  defp price_cents(price), do: round(price * 100)

  # Fills one order and tells its portfolio's LiveViews what happened. A failed fill (e.g. not
  # enough cash any more) leaves the order "rejected"; an order cancelled a moment ago is
  # :not_open, which is expected and not reported.
  defp fill(%PendingOrder{} = order, fill_cents) do
    case Trading.fill_pending_order(order.id, fill_cents) do
      {:ok, %{order: filled} = result} ->
        oco = if result.cancelled > 0, do: " The other exit was cancelled (OCO).", else: ""
        notify(order, :ok, "#{label(order)}: #{Trading.confirmation(filled)}.#{oco}")

      {:error, :not_open} ->
        :ok

      {:error, reason} ->
        Logger.info("[OrderWatcher] #{Trading.describe(order)} rejected: #{reason}")

        notify(
          order,
          :error,
          "Rejected #{Trading.describe(order)}: #{Trading.error_message(reason)}"
        )
    end
  end

  defp label(%PendingOrder{type: "stop"}), do: "Stop-loss triggered"
  defp label(%PendingOrder{parent_id: nil}), do: "Limit order filled"
  defp label(%PendingOrder{}), do: "Take-profit filled"

  defp notify(order, kind, text) do
    Phoenix.PubSub.broadcast(
      StockFetcher.PubSub,
      Trading.portfolio_topic(order.portfolio_id),
      {:pending_order_event, kind, text}
    )
  end

  defp default_topics(:live), do: ["stocks:live", "stocks:extra"]
  defp default_topics(:mock), do: ["stocks:mock", "stocks:mock:extra"]
end
