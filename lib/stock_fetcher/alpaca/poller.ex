defmodule StockFetcher.Alpaca.Poller do
  @moduledoc """
  Live prices for the 45 tickers Finnhub doesn't cover (PLAN.md step B2, built 2026-11-07).

  Every 15 s during market hours it makes **one** request to Alpaca's free market-data API
  (latest trades, IEX feed) for all 45 symbols, and broadcasts each new trade on
  "stocks:extra" in the same payload shape as the Finnhub Worker
  (`{"new_price", %{id, ticker, price, timestamp}}`), so consumers can't tell the sources
  apart. That's 4 requests a minute out of the free tier's 200.

  Why a separate topic and not "stocks:live": the React SPA adds every ticker it hears about
  and was built for 5. `PricesLive` and the live `OrderWatcher` subscribe to both topics.

  Why not saved to the DB like Finnhub prices: the React SPA's history endpoints read every
  ticker in `stock_prices`, so saving these would change React too. The poller keeps the latest
  trade per ticker in its own state instead (`latest/1`), which is all `PricesLive` needs on
  mount; the chart history comes from `StockFetcher.Candles`.

  It also polls once at startup, even when the market is closed, so the page shows Friday's
  last prices on a weekend instead of nothing. A trade is only re-broadcast when it is newer
  than the one already seen, so a quiet ticker doesn't spam the topic.

  Data only: this module never calls Alpaca's trading endpoints. Keys come from
  `ALPACA_KEY_ID` / `ALPACA_SECRET` and are never logged. Without them it doesn't start polling.

  Testable like the Worker: `:now_fn`, `:schedule_timer`, and HTTP stubbed through
  `config :stock_fetcher, :req_options` (Req.Test in tests).
  """
  use GenServer
  require Logger

  alias StockFetcher.{MarketHours, Tickers}

  @url "https://data.alpaca.markets/v2/stocks/trades/latest"
  @interval 15_000
  @topic "stocks:extra"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The latest trade seen per ticker, as broadcast payloads. `[]` if not running."
  def latest(name \\ __MODULE__) do
    if GenServer.whereis(name), do: GenServer.call(name, :latest), else: []
  end

  @doc "True when the Alpaca keys are set (used to decide whether to start polling)."
  def configured? do
    System.get_env("ALPACA_KEY_ID") not in [nil, ""] and
      System.get_env("ALPACA_SECRET") not in [nil, ""]
  end

  @impl true
  def init(opts) do
    state = %{
      symbols: Keyword.get(opts, :symbols, Tickers.extra()),
      topic: Keyword.get(opts, :topic, @topic),
      now_fn: Keyword.get(opts, :now_fn, &DateTime.utc_now/0),
      schedule_timer: Keyword.get(opts, :schedule_timer, true),
      # ticker => last payload (what latest/1 returns) and ticker => exact trade time.
      latest: %{},
      seen: %{},
      first_poll: true
    }

    if state.schedule_timer, do: send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_call(:latest, _from, state), do: {:reply, Map.values(state.latest), state}

  @impl true
  def handle_info(:poll, state) do
    state =
      if state.first_poll or MarketHours.market_open?(state.now_fn.()) do
        poll(%{state | first_poll: false})
      else
        state
      end

    if state.schedule_timer, do: Process.send_after(self(), :poll, @interval)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # --- Helpers for handle_info ---

  defp poll(state) do
    case fetch(state.symbols) do
      {:ok, trades} ->
        Enum.reduce(trades, state, fn {ticker, trade}, acc ->
          maybe_broadcast(acc, ticker, trade)
        end)

      {:error, reason} ->
        # The reason is a status code or an exception message, never the request headers.
        Logger.warning("[Alpaca.Poller] latest trades failed: #{inspect(reason)}")
        state
    end
  end

  defp fetch(symbols) do
    options =
      [
        url: @url,
        params: [symbols: Enum.join(symbols, ","), feed: "iex"],
        headers: [
          {"APCA-API-KEY-ID", System.get_env("ALPACA_KEY_ID", "")},
          {"APCA-API-SECRET-KEY", System.get_env("ALPACA_SECRET", "")}
        ],
        receive_timeout: 10_000
      ] ++ Application.get_env(:stock_fetcher, :req_options, [])

    case Req.get(options) do
      {:ok, %Req.Response{status: 200, body: %{"trades" => trades}}} when is_map(trades) ->
        {:ok, trades}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  # Broadcast only trades newer than the last one seen for this ticker.
  defp maybe_broadcast(state, ticker, %{"p" => price, "t" => time}) when is_number(price) do
    with {:ok, timestamp, _offset} <- DateTime.from_iso8601(time),
         true <- newer?(state.seen[ticker], timestamp) do
      payload = %{
        id: System.unique_integer([:positive]),
        ticker: ticker,
        price: price / 1,
        timestamp: DateTime.truncate(timestamp, :second)
      }

      Phoenix.PubSub.broadcast(StockFetcher.PubSub, state.topic, {"new_price", payload})

      %{
        state
        | latest: Map.put(state.latest, ticker, Map.delete(payload, :id)),
          seen: Map.put(state.seen, ticker, timestamp)
      }
    else
      _ -> state
    end
  end

  defp maybe_broadcast(state, _ticker, _trade), do: state

  defp newer?(nil, _timestamp), do: true
  defp newer?(seen, timestamp), do: DateTime.compare(timestamp, seen) == :gt
end
