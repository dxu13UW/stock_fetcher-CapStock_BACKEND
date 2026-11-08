defmodule StockFetcher.Candles do
  @moduledoc """
  Candlestick history for the chart (2026-11-07), one process per price source.

  Where candles come from, without a per-page-view API call (CLAUDE.md constraint):
    * **Live:** at boot, and every 30 minutes while the market is open, a few paged requests to
      Alpaca's historical bars endpoint fetch 4 days of 5-minute bars for all 50 tickers from the SIP
      feed (every exchange, so highs, lows and volume are right). The free tier only allows SIP
      data at least 15 minutes old, so the newest bars stop 16 minutes ago. The minutes after
      that are built here from the live ticks (Finnhub and Alpaca IEX), and replaced by the
      accurate SIP bar on the next refresh.
    * **Mock:** a made-up history (a random walk ending at the mock stream's starting prices)
      at boot, then real candles built from the mock ticks, 1 minute each so they fill quickly.

  Every page asks this process (`get/2`), so 1 or 100 open tabs cost the same number of Alpaca
  requests: about 4 every 30 minutes. A tab then keeps its chart current itself, by folding
  each new tick into the last candle in the browser (the `Chart` hook in app.js).

  Kept in memory, not the DB: it's a cache that rebuilds in one request after a restart, and
  the React SPA's history endpoints read every ticker in `stock_prices`, so saving there would
  change React too.

  Each candle is `%{time: unix_seconds, open:, high:, low:, close:}` (floats, display only).
  """
  use GenServer
  require Logger

  alias StockFetcher.{MarketHours, Tickers}

  @bars_url "https://data.alpaca.markets/v2/stocks/bars"
  @keep 240
  @refresh_ms 30 * 60 * 1000

  def start_link(opts) do
    source = Keyword.fetch!(opts, :source)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, name(source)))
  end

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :source)}, start: {__MODULE__, :start_link, [opts]}}
  end

  def name(:live), do: __MODULE__.Live
  def name(:mock), do: __MODULE__.Mock

  @doc "Seconds per candle: 5 minutes live, 1 minute mock."
  def interval(:live), do: 300
  def interval(:mock), do: 60

  @doc "Candles for one ticker, oldest first. `[]` if none or the process isn't running."
  def get(source, ticker, name \\ nil) do
    server = name || name(source)
    if GenServer.whereis(server), do: GenServer.call(server, {:get, ticker}), else: []
  end

  @impl true
  def init(opts) do
    source = Keyword.fetch!(opts, :source)
    topics = Keyword.get(opts, :topics, default_topics(source))
    Enum.each(topics, &Phoenix.PubSub.subscribe(StockFetcher.PubSub, &1))

    state = %{
      source: source,
      interval: interval(source),
      candles: if(source == :mock, do: mock_history(), else: %{}),
      fetch_bars: Keyword.get(opts, :fetch_bars, source == :live),
      now_fn: Keyword.get(opts, :now_fn, &DateTime.utc_now/0)
    }

    # 10 s after boot, so the first fetch doesn't add to the app's own startup memory spike on
    # the small Fly machine.
    if state.fetch_bars, do: Process.send_after(self(), :refresh, 10_000)
    {:ok, state}
  end

  @impl true
  def handle_call({:get, ticker}, _from, state) do
    {:reply, Map.get(state.candles, ticker, []), state}
  end

  @impl true
  def handle_info({"new_price", %{ticker: ticker, price: price, timestamp: at}}, state)
      when is_number(price) do
    time = div(unix(at), state.interval) * state.interval
    {:noreply, update_in(state.candles, &fold_tick(&1, ticker, time, price / 1))}
  end

  # Boot, then every 30 minutes; only fetches while the market is open (and once at boot, so a
  # weekend page still shows Friday).
  def handle_info(:refresh, state) do
    first? = not Map.has_key?(state, :refreshed)

    state =
      if first? or MarketHours.market_open?(state.now_fn.()) do
        case fetch_bars(state.now_fn.()) do
          {:ok, bars} ->
            Map.update!(state, :candles, &merge_bars(&1, bars))

          {:error, reason} ->
            Logger.warning("[Candles] Alpaca bars failed: #{inspect(reason)}")
            state
        end
      else
        state
      end

    Process.send_after(self(), :refresh, @refresh_ms)
    # Drop the decoded pages' garbage now rather than whenever the heap next fills.
    :erlang.garbage_collect()
    {:noreply, Map.put(state, :refreshed, true)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # --- Building candles ---

  @doc false
  # Folds one tick into a ticker's candles: same bucket -> widen the last candle; newer bucket
  # -> start a new one; older (a late tick) -> ignored.
  def fold_tick(candles, ticker, time, price) do
    Map.update(candles, ticker, [candle(time, price)], fn list ->
      case List.last(list) do
        %{time: ^time} = last ->
          List.replace_at(list, -1, %{
            last
            | high: max(last.high, price),
              low: min(last.low, price),
              close: price
          })

        %{time: last_time} when time > last_time ->
          Enum.take(list ++ [candle(time, price)], -@keep)

        _older ->
          list
      end
    end)
  end

  defp candle(time, price), do: %{time: time, open: price, high: price, low: price, close: price}

  # SIP bars win for every bucket they cover; tick-built candles newer than the last bar stay.
  defp merge_bars(candles, bars) do
    Enum.reduce(bars, candles, fn {ticker, list}, acc ->
      last_bar = List.last(list).time
      newer = acc |> Map.get(ticker, []) |> Enum.filter(&(&1.time > last_bar))
      Map.put(acc, ticker, Enum.take(list ++ newer, -@keep))
    end)
  end

  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)

  defp unix(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp default_topics(:live), do: ["stocks:live", "stocks:extra"]
  defp default_topics(:mock), do: ["stocks:mock", "stocks:mock:extra"]

  # --- Alpaca historical bars ---

  defp fetch_bars(now) do
    if StockFetcher.Alpaca.Poller.configured?() do
      params = [
        symbols: Enum.join(Tickers.all(), ","),
        timeframe: "5Min",
        start:
          now |> DateTime.add(-4, :day) |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        end:
          now |> DateTime.add(-16, :minute) |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        feed: "sip",
        adjustment: "split",
        limit: 5_000
      ]

      fetch_pages(params, nil, %{}, 0)
    else
      {:error, :no_alpaca_keys}
    end
  end

  # Follows next_page_token. SIP bars include pre- and after-market (4:00-20:00 ET, 192 bars a
  # day), so 50 tickers x 4 days is ~8 pages of 5,000; capped at 16 in case of a loop.
  #
  # Memory: each page is turned into compact candles and trimmed to @keep per ticker *before*
  # the next page is fetched, so only one page of raw JSON is alive at a time. The first
  # version kept every raw page (~40,000 decoded bar maps) and the 256 MB Fly machine was
  # OOM-killed at boot (2026-11-08).
  defp fetch_pages(_params, _token, acc, 16), do: {:ok, acc}

  defp fetch_pages(params, token, acc, page) do
    params = if token, do: Keyword.put(params, :page_token, token), else: params

    options =
      [
        url: @bars_url,
        params: params,
        headers: [
          {"APCA-API-KEY-ID", System.get_env("ALPACA_KEY_ID", "")},
          {"APCA-API-SECRET-KEY", System.get_env("ALPACA_SECRET", "")}
        ],
        receive_timeout: 20_000
      ] ++ Application.get_env(:stock_fetcher, :req_options, [])

    case Req.get(options) do
      {:ok, %Req.Response{status: 200, body: %{"bars" => bars} = body}} ->
        # Pages run by symbol, then time, so a ticker split across pages continues in order.
        acc = Map.merge(acc, finish(bars || %{}), fn _t, a, b -> Enum.take(a ++ b, -@keep) end)
        next = body["next_page_token"]

        if is_binary(next), do: fetch_pages(params, next, acc, page + 1), else: {:ok, acc}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp finish(raw) do
    raw
    |> Enum.map(fn {ticker, bars} ->
      {ticker,
       bars |> Enum.flat_map(&bar_candle/1) |> Enum.sort_by(& &1.time) |> Enum.take(-@keep)}
    end)
    |> Enum.reject(fn {_t, list} -> list == [] end)
    |> Map.new()
  end

  # One Alpaca bar -> [candle], or [] if its time doesn't parse.
  defp bar_candle(%{"t" => t, "o" => o, "h" => h, "l" => l, "c" => c}) do
    case DateTime.from_iso8601(t) do
      {:ok, at, _} ->
        [%{time: DateTime.to_unix(at), open: o / 1, high: h / 1, low: l / 1, close: c / 1}]

      _ ->
        []
    end
  end

  defp bar_candle(_bar), do: []

  # --- Mock history ---

  # 120 one-minute candles per ticker, a random walk that ends at the mock starting price, so
  # the first live mock tick continues the chart without a jump. Steps of up to ±0.5% a minute,
  # about what the mock stream itself moves, so history and live candles look alike.
  defp mock_history do
    now = div(System.os_time(:second), 60) * 60
    prices = Map.merge(Tickers.mock_prices(:finnhub), Tickers.mock_prices(:extra))

    Map.new(prices, fn {ticker, end_price} ->
      {candles, _} =
        Enum.map_reduce(1..120, end_price, fn i, close ->
          step = close * 0.005
          open = Float.round(max(close + (:rand.uniform() - 0.5) * 2 * step, 0.5), 2)
          high = Float.round(max(open, close) + :rand.uniform() * step, 2)
          low = Float.round(max(min(open, close) - :rand.uniform() * step, 0.1), 2)
          {%{time: now - i * 60, open: open, high: high, low: low, close: close}, open}
        end)

      {ticker, Enum.reverse(candles)}
    end)
  end
end
