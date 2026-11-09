defmodule StockFetcherWeb.PricesLive do
  @moduledoc """
  Live prices (PLAN.md step B) and the LiveView trading app, at /prices.

  One of these processes runs per open browser tab. It holds the page state in
  `socket.assigns`; whenever assigns change, LiveView re-runs `render/1` and sends only the
  changed parts of the HTML to the browser.

  `@prices` is `%{ticker => %{ticker, price, timestamp, prev}}`: the broadcast payload shape,
  plus the previous price so the watchlist can show which way the last tick went.

  Layout (2026-11-07): a left sidebar with the portfolio card (value, P/L, save file, new
  portfolio) and the four exit strategies (long/short x take-profit/stop-loss) as an accordion;
  the main column has a candlestick chart, the quick market-order forms, a scrollable 50-ticker
  watchlist, and positions / open orders / history. A help panel explains paper trading.

  The portfolio is **private to this tab** (2026-11-07): a session portfolio created on connect
  and deleted when the tab closes (`Trading.SessionJanitor`). The browser keeps the progress:
  every change pushes a signed save file to the `SaveFile` hook (localStorage autosave), and the
  next connect sends it back in the connect params, so a reload or reconnect resumes where it
  left off. The user can download the file and import it later. No accounts.

  The benchmark panel (`#order-form`, Buy/Sell) still matches the React panel field for field;
  React keeps using the shared demo portfolio through the API.
  """
  use StockFetcherWeb, :live_view

  alias StockFetcher.{Candles, MarketHours, Tickers, Trading}
  alias StockFetcher.Trading.{SaveFile, SessionJanitor}
  alias StockFetcherWeb.Glossary

  @exit_fields ["quantity", "limit", "stop", "take_profit"]

  # The four exit strategies in the sidebar. `direction` goes to Trading.place_limit_order/6;
  # `exit` is the one the panel teaches (required in its form), the other stays optional.
  # `jump` is the panel's key (home row, top to bottom); see jump_label/1.
  @panels [
    %{
      id: "long_tp",
      direction: "long",
      exit: :take_profit,
      title: "Long · take-profit",
      jump: "a"
    },
    %{id: "long_sl", direction: "long", exit: :stop, title: "Long · stop-loss", jump: "d"},
    %{
      id: "short_tp",
      direction: "short",
      exit: :take_profit,
      title: "Short · take-profit",
      jump: "f"
    },
    %{id: "short_sl", direction: "short", exit: :stop, title: "Short · stop-loss", jump: "g"}
  ]

  # mount/3 runs twice: once in a one-shot process for the plain HTTP render, then again in
  # the long-lived LiveView process when the WebSocket connects (see LOG.md, TODO 1).
  # Prices load on both runs so the first HTML has data. The portfolio only exists once
  # connected: it belongs to the long-lived process, and the browser's autosave arrives in the
  # connect params.
  #
  # Two sources, like the React app's two channel topics:
  #   /prices              -> "stocks:live" (Finnhub, 5 tickers) + "stocks:extra" (Alpaca, 45)
  #   /prices?source=mock  -> "stocks:mock" + "stocks:mock:extra" (Mock.Streamer, never saved)
  @impl true
  def mount(params, _session, socket) do
    source = if params["source"] == "mock", do: :mock, else: :live
    prices = initial_prices(source)
    tickers = prices |> Map.keys() |> Enum.concat(Tickers.all()) |> Enum.uniq() |> Enum.sort()
    selected = if "AAPL" in tickers, do: "AAPL", else: List.first(tickers)

    socket =
      assign(socket,
        source: source,
        prices: prices,
        # Its own assign, so a price tick doesn't re-send the dropdown options (only a new ticker
        # does). Re-rendering a <select> closes it and resets the choice.
        tickers: tickers,
        selected: selected,
        market_open: market_open?(),
        # What the user has typed/selected, kept on the server via phx-change. LiveView only
        # protects the focused input from re-renders; without this, every tick would reset the
        # other fields to the rendered defaults.
        # Every form trades @selected (the watchlist's choice), so only the typed fields are kept.
        order_form: %{"quantity" => "1"},
        short_form: %{"quantity" => "1"},
        exit_form: %{
          "quantity" => "1",
          "limit" => "",
          "stop" => "",
          "take_profit" => ""
        },
        # All four exit panels start closed, so the sidebar shows every choice at once (2026-11-08).
        open_panel: nil,
        panels: @panels,
        portfolio: nil,
        orders: [],
        pending: [],
        # @pending grouped for the Open orders card (brackets + waiting entries).
        order_groups: [],
        # The open-order card shown on the chart (its group id), or nil.
        focused: nil,
        # nil, or {:ok, text} / {:error, text} from the last action
        message: nil,
        # The replaced portfolio's save after "New portfolio" or "Import", so one click can bring
        # it back (instead of a blocking "are you sure?" popup). Cleared by the next trade.
        undo: nil
      )

    cond do
      not connected?(socket) ->
        {:ok, socket}

      # Too many new connections from one IP: show prices' first render, but no live process
      # work (no subscriptions, no portfolio row). See guard_process/1 and connection_allowed?/1.
      not connection_allowed?(socket) ->
        {:ok,
         assign(socket,
           message:
             {:error, "Too many connections from your network. Wait a minute, then reload."}
         )}

      true ->
        guard_process()
        Enum.each(topics(source), &Phoenix.PubSub.subscribe(StockFetcher.PubSub, &1))

        {portfolio, message} = start_portfolio(source, get_connect_params(socket)["save"])

        {:ok,
         socket
         |> use_portfolio(portfolio)
         |> assign(message: message)
         |> attach_hook(:event_rate_limit, :handle_event, &limit_events/3)
         |> push_chart()}
    end
  end

  # --- Abuse and memory guards (2026-11-08) ---
  # Every connected tab is a process on a small (256 MB) machine. Three guards, plus the
  # connection limits in fly.toml and the frame-size caps in endpoint.ex:

  # 1. A memory ceiling for this process. A runaway tab (e.g. a huge decoded message) is killed
  #    alone instead of growing until the whole VM is OOM-killed. Normal use is well under 1 MB;
  #    importing a 1 MB save peaks at a few MB. The janitor then deletes its portfolio and the
  #    browser reconnects and restores from its autosave. (Counts the process heap; large binaries
  #    live off-heap and are capped by the socket's frame size.)
  @max_heap_words div(50_000_000, :erlang.system_info(:wordsize))

  defp guard_process do
    Process.flag(:max_heap_size, %{size: @max_heap_words, kill: true, error_logger: true})
  end

  # 2. New LiveView connections per client IP per minute (Hammer, one ETS row per IP per minute).
  #    Behind Fly the IP is the Fly-Client-IP header, which Fly's proxy sets; locally, the peer.
  #    Generous enough for one person's tabs and reconnects after a deploy.
  defp connection_allowed?(socket) do
    # 200 a minute per IP (was 30): a classroom behind one campus IP counts as one client, and
    # every page load or Live/Mock switch is a new connection. Fly's proxy still caps the total
    # at 250 open connections (fly.toml), which is what protects memory.
    limit = Application.get_env(:stock_fetcher, :lv_connections_per_minute, 200)

    match?(
      {:allow, _},
      Hammer.check_rate("lv_connect:#{client_ip(socket)}", 60_000, limit)
    )
  end

  defp client_ip(socket) do
    fly_ip =
      Enum.find_value(get_connect_info(socket, :x_headers) || [], fn
        {"fly-client-ip", ip} -> ip
        _ -> nil
      end)

    case {fly_ip, get_connect_info(socket, :peer_data)} do
      {ip, _} when is_binary(ip) -> ip
      {nil, %{address: address}} -> address |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  # 3. Events per tab per second. Kept in this process's own dictionary, not a shared table: it
  #    costs nothing and disappears with the tab. A real user, even typing (debounced 250 ms) and
  #    clicking fast, stays far below; a script sending orders or imports in a loop is cut off.
  #    The JSON API has its own per-IP limits (HydrationLimiter).
  defp limit_events(_event, _params, socket) do
    limit = Application.get_env(:stock_fetcher, :lv_events_per_second, 20)
    now = System.monotonic_time(:second)

    count =
      case Process.get(:event_window) do
        {^now, n} -> n + 1
        _ -> 1
      end

    Process.put(:event_window, {now, count})

    if count > limit,
      do:
        {:halt,
         assign(socket, message: {:error, "Too many actions at once. Slow down a little."})},
      else: {:cont, socket}
  end

  defp topics(:live), do: ["stocks:live", "stocks:extra"]
  defp topics(:mock), do: ["stocks:mock", "stocks:mock:extra"]

  defp initial_prices(:live) do
    db =
      Enum.map(StockFetcher.latest_prices(), fn row ->
        %{ticker: row.ticker, price: row.price, timestamp: row.inserted_at}
      end)

    prices = to_price_map(db ++ StockFetcher.Alpaca.Poller.latest())

    # A ticker with no tick yet (e.g. after a weekend restart) shows the last candle's close,
    # so the watchlist is never blank. Live orders are rejected after hours anyway, and the
    # first real tick replaces it.
    Tickers.all()
    |> Enum.reject(&Map.has_key?(prices, &1))
    |> Enum.reduce(prices, fn ticker, acc ->
      case List.last(Candles.get(:live, ticker)) do
        %{time: time, close: close} ->
          at = DateTime.from_unix!(time + Candles.interval(:live))
          Map.put(acc, ticker, %{ticker: ticker, price: close, timestamp: at, prev: nil})

        nil ->
          acc
      end
    end)
  end

  # Mock prices live in the two streamers' state; asking them avoids a blank page for 1.5 s.
  defp initial_prices(:mock) do
    to_price_map(
      StockFetcher.Mock.Streamer.current_prices() ++
        StockFetcher.Mock.Streamer.current_prices(StockFetcher.Mock.Streamer.Extra)
    )
  end

  defp to_price_map(list) do
    Map.new(list, fn p ->
      {p.ticker, %{ticker: p.ticker, price: p.price, timestamp: p.timestamp, prev: nil}}
    end)
  end

  defp market_open? do
    MarketHours.market_open?(
      Application.get_env(:stock_fetcher, :trading_fixed_now) || DateTime.utc_now()
    )
  end

  # The browser's autosave if it has one and it loads, else a fresh $100,000 portfolio.
  defp start_portfolio(source, save) when is_binary(save) and save != "" do
    case SaveFile.import(save, source) do
      {:ok, portfolio} ->
        {portfolio, nil}

      {:error, reason} ->
        {:ok, portfolio} = Trading.create_session_portfolio(source)

        {portfolio,
         {:error,
          "Your browser's autosave couldn't be loaded (#{SaveFile.error_message(reason)}) " <>
            "Started a new $100,000 portfolio."}}
    end
  end

  defp start_portfolio(source, _no_save) do
    {:ok, portfolio} = Trading.create_session_portfolio(source)
    {portfolio, nil}
  end

  # Makes `portfolio` this tab's portfolio: the janitor deletes it when the tab closes, and
  # OrderWatcher reports its resting-order fills on its topic. A replaced portfolio is deleted.
  defp use_portfolio(socket, portfolio) do
    if old = socket.assigns.portfolio do
      Phoenix.PubSub.unsubscribe(StockFetcher.PubSub, Trading.portfolio_topic(old.id))
      SessionJanitor.forget(old.id)
      Trading.delete_session_portfolio(old.id)
    end

    SessionJanitor.register(portfolio.id)
    Phoenix.PubSub.subscribe(StockFetcher.PubSub, Trading.portfolio_topic(portfolio.id))

    socket |> assign(portfolio: portfolio) |> reload_trading()
  end

  # Every price broadcast on the subscribed topics lands here. Map.take drops the payload's
  # `id`, so entries match the mount shape. The chart only gets ticks for the selected ticker.
  @impl true
  def handle_info({"new_price", payload}, socket) do
    price = Map.take(payload, [:ticker, :price, :timestamp])
    prev = get_in(socket.assigns.prices, [price.ticker, :price])
    socket = update(socket, :prices, &Map.put(&1, price.ticker, Map.put(price, :prev, prev)))

    socket =
      if price.ticker in socket.assigns.tickers,
        do: socket,
        else: update(socket, :tickers, &Enum.sort([price.ticker | &1]))

    socket =
      if price.ticker == socket.assigns.selected,
        do: push_event(socket, "chart:tick", %{price: price.price, time: unix(price.timestamp)}),
        else: socket

    {:noreply, assign(socket, market_open: socket.assigns.source == :mock or market_open?())}
  end

  # From OrderWatcher: a resting order filled or was rejected. The DB already changed, so reload.
  def handle_info({:pending_order_event, kind, text}, socket) do
    {:noreply, socket |> reload_trading() |> assign(message: {kind, text})}
  end

  # The form's button that was clicked arrives as "side" (the submitter's name/value): Buy/Sell
  # from #order-form (the benchmark panel), Short/Cover from #short-form (LiveView only). Same
  # handler, because Trading.place_market_order/6 takes all four sides.
  @impl true
  def handle_event("order", %{"ticker" => ticker, "quantity" => quantity, "side" => side}, socket) do
    # Step D: the price is the one this page is showing; nil if the ticker has none.
    price = get_in(socket.assigns.prices, [ticker, :price])

    result =
      Trading.place_market_order(socket.assigns.portfolio.id, side, ticker, quantity, price,
        source: socket.assigns.source
      )

    message =
      case result do
        {:ok, %{order: order}} -> {:ok, Trading.confirmation(order)}
        {:error, reason} -> {:error, Trading.error_message(reason)}
      end

    {:noreply, socket |> reload_trading() |> assign(message: message, undo: nil)}
  end

  # phx-change: remember the form's current values so re-renders keep them.
  def handle_event("order_form", params, socket),
    do: {:noreply, assign(socket, order_form: Map.take(params, ["quantity"]))}

  def handle_event("short_form", params, socket),
    do: {:noreply, assign(socket, short_form: Map.take(params, ["quantity"]))}

  def handle_event("exit_form", params, socket),
    do: {:noreply, assign(socket, exit_form: Map.take(params, @exit_fields))}

  # Accordion: opening one panel closes the others (one assign, so only one can be open).
  def handle_event("toggle_panel", %{"panel" => id}, socket) do
    {:noreply, assign(socket, open_panel: if(socket.assigns.open_panel == id, do: nil, else: id))}
  end

  # Fills the open panel with example prices around the current one, so a first-time user sees
  # a valid setup: entry 0.5% better than now, stop 3% against it, take-profit 5% for it.
  def handle_event("suggest", %{"panel" => id}, socket) do
    panel = Enum.find(@panels, &(&1.id == id))
    form = socket.assigns.exit_form

    case get_in(socket.assigns.prices, [socket.assigns.selected, :price]) do
      nil ->
        {:noreply, assign(socket, message: {:error, Trading.error_message(:unknown_ticker)})}

      price ->
        sign = if panel.direction == "long", do: 1, else: -1

        form =
          Map.merge(form, %{
            "limit" => dollars(round(price * (1 - sign * 0.005) * 100)),
            "stop" => dollars(round(price * (1 - sign * 0.03) * 100)),
            "take_profit" => dollars(round(price * (1 + sign * 0.05) * 100))
          })

        {:noreply, assign(socket, exit_form: form)}
    end
  end

  # Limit entry (long or short) with an optional stop-loss and take-profit, from an exit panel.
  def handle_event("limit_order", params, socket) do
    %{"ticker" => ticker, "quantity" => quantity, "limit" => limit} = params
    portfolio_id = socket.assigns.portfolio.id

    result =
      Trading.place_limit_order(portfolio_id, ticker, quantity, limit, params["stop"],
        direction: params["direction"] || "long",
        take_profit: params["take_profit"],
        source: socket.assigns.source,
        current_price: get_in(socket.assigns.prices, [ticker, :price])
      )

    message =
      case result do
        {:ok, :placed, pending} -> {:ok, "Placed #{Trading.describe(pending)}."}
        {:ok, :filled, %{order: order}} -> {:ok, "Filled now: " <> Trading.confirmation(order)}
        {:error, reason} -> {:error, Trading.error_message(reason)}
      end

    {:noreply, socket |> reload_trading() |> assign(message: message, undo: nil)}
  end

  def handle_event("cancel_order", %{"id" => id}, socket) do
    message =
      case Trading.cancel_pending_order(socket.assigns.portfolio.id, id) do
        {:ok, pending} -> {:ok, "Cancelled #{Trading.describe(pending)}."}
        {:error, reason} -> {:error, Trading.error_message(reason)}
      end

    {:noreply, socket |> reload_trading() |> assign(message: message, undo: nil)}
  end

  # Move an open stop-loss or take-profit. The current price comes from this page, like a
  # market order's, so "would this fill right now?" is judged against what the user sees.
  def handle_event("amend_order", %{"order_id" => id, "trigger" => trigger}, socket) do
    ticker =
      Enum.find_value(socket.assigns.pending, fn p -> if "#{p.id}" == id, do: p.ticker end)

    result =
      Trading.amend_order(socket.assigns.portfolio.id, id, trigger,
        current_price: get_in(socket.assigns.prices, [ticker, :price])
      )

    message =
      case result do
        {:ok, pending} -> {:ok, "Moved: #{Trading.describe(pending)}."}
        {:error, reason} -> {:error, Trading.error_message(reason)}
      end

    {:noreply, socket |> reload_trading() |> assign(message: message, undo: nil)}
  end

  # A watchlist row was clicked (or flash-jumped to): chart it. Every form trades @selected, so
  # this one assign is also what Buy, Short and the exit panels will trade.
  def handle_event("select_ticker", %{"ticker" => ticker}, socket) do
    if ticker in socket.assigns.tickers do
      {:noreply, socket |> assign(selected: ticker, focused: nil) |> push_chart() |> push_lines()}
    else
      {:noreply, socket}
    end
  end

  # An open-order card was clicked: chart its ticker and draw its prices as dotted lines (blue
  # take-profit, orange stop-loss, grey entry), the same colours as its chips. Clicking the
  # focused card again clears it.
  def handle_event("focus_order", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.order_groups, &("#{&1.id}" == id)) do
      nil ->
        {:noreply, socket}

      %{id: group_id} when group_id == socket.assigns.focused ->
        {:noreply, socket |> assign(focused: nil) |> push_lines()}

      group ->
        {:noreply,
         socket
         |> assign(selected: group_ticker(group), focused: group.id)
         |> push_chart()
         |> push_lines()}
    end
  end

  # A new portfolio with the buying power the user picked ($1,000 to $2,000,000).
  # No confirmation popup: it replaces the portfolio at once and offers Undo (see @undo).
  def handle_event("new_portfolio", %{"starting_cash" => amount}, socket) do
    case Trading.create_session_portfolio(socket.assigns.source, amount) do
      {:ok, portfolio} ->
        {:noreply,
         socket
         |> keep_for_undo()
         |> use_portfolio(portfolio)
         |> assign(
           message:
             {:ok, "Started a new portfolio with #{Trading.format_cents(portfolio.cash_cents)}."}
         )}

      {:error, reason} ->
        {:noreply, assign(socket, message: {:error, Trading.error_message(reason)})}
    end
  end

  # The SaveFile hook read a file the user picked and sent its text.
  def handle_event("import_save", %{"file" => text}, socket) when is_binary(text) do
    case SaveFile.import(text, socket.assigns.source) do
      {:ok, portfolio} ->
        {:noreply,
         socket
         |> keep_for_undo()
         |> use_portfolio(portfolio)
         |> assign(message: {:ok, "Save file loaded."})}

      {:error, reason} ->
        {:noreply, assign(socket, message: {:error, SaveFile.error_message(reason)})}
    end
  end

  def handle_event("import_save", %{"too_large" => _}, socket),
    do: {:noreply, assign(socket, message: {:error, SaveFile.error_message(:too_large)})}

  # Brings back the portfolio that "New portfolio" or "Import" replaced, from its save.
  def handle_event("undo", _params, %{assigns: %{undo: save}} = socket) when is_binary(save) do
    case SaveFile.import(save, socket.assigns.source) do
      {:ok, portfolio} ->
        {:noreply,
         socket
         |> use_portfolio(portfolio)
         |> assign(undo: nil, message: {:ok, "Your previous portfolio is back."})}

      {:error, reason} ->
        {:noreply, assign(socket, undo: nil, message: {:error, SaveFile.error_message(reason)})}
    end
  end

  def handle_event("undo", _params, socket), do: {:noreply, socket}

  # Saves the current portfolio for Undo before it's replaced. Skipped when it's untouched
  # (no trades, no open orders, cash as it started): there's nothing to lose, and keeping the
  # existing Undo means "New" twice in a row can still bring back the one that had trades.
  defp keep_for_undo(%{assigns: %{portfolio: p, orders: orders, pending: pending}} = socket) do
    untouched? =
      orders == [] and pending == [] and p.positions == [] and
        p.cash_cents == Trading.starting_cash(p)

    save =
      if untouched?, do: socket.assigns.undo, else: SaveFile.export(p.id, socket.assigns.source)

    assign(socket, undo: save)
  end

  # Reloads the portfolio and its orders after any change, and autosaves: the SaveFile hook
  # stores the new save in the browser, so the server never has to keep it.
  defp reload_trading(socket) do
    id = socket.assigns.portfolio.id

    socket
    |> assign(
      portfolio: Trading.get_portfolio!(id),
      orders: Trading.list_orders(id),
      pending: Trading.list_pending_orders(id),
      order_groups: Trading.open_order_groups(id)
    )
    |> refresh_focus()
    |> push_event("save", %{
      source: socket.assigns.source,
      file: SaveFile.export(id, socket.assigns.source)
    })
  end

  # Keeps the chart's order lines in step with the orders: a Move shifts its line; a fill or
  # cancel that ends the focused group clears them.
  defp refresh_focus(%{assigns: %{focused: nil}} = socket), do: socket

  defp refresh_focus(socket) do
    if Enum.any?(socket.assigns.order_groups, &(&1.id == socket.assigns.focused)),
      do: push_lines(socket),
      else: socket |> assign(focused: nil) |> push_lines()
  end

  # The focused group's prices for the Chart hook, or [] to clear.
  defp push_lines(socket) do
    group = Enum.find(socket.assigns.order_groups, &(&1.id == socket.assigns.focused))
    push_event(socket, "chart:lines", %{lines: if(group, do: order_lines(group), else: [])})
  end

  defp group_ticker(%{kind: :bracket, ticker: ticker}), do: ticker
  defp group_ticker(%{kind: :entry, order: order}), do: order.ticker

  # Line colours match the chips (exit_chip/1): blue take-profit, orange stop-loss, grey entry.
  # Not green/red: those already mean up/down candles and the last-price line.
  @line_colors %{take_profit: "#3b82f6", stop: "#f97316", entry: "#a1a1aa"}

  defp order_lines(%{kind: :bracket, exits: exits}) do
    Enum.map(exits, fn e ->
      kind = if e.type == "stop", do: :stop, else: :take_profit
      line(e.trigger_cents, kind)
    end)
  end

  # A waiting entry: its price, plus the stop and take-profit it will open.
  defp order_lines(%{kind: :entry, order: o}) do
    [
      line(o.trigger_cents, :entry),
      line(o.stop_cents, :stop),
      line(o.take_profit_cents, :take_profit)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp line(nil, _kind), do: nil

  defp line(cents, kind) do
    title = %{take_profit: "TP", stop: "SL", entry: "Entry"}[kind]
    %{price: cents / 100, color: @line_colors[kind], title: title}
  end

  # Sends the selected ticker's candle history to the Chart hook (Candles is a cache; no API
  # call per page view). Later ticks for it go out as "chart:tick" from handle_info.
  defp push_chart(socket) do
    %{source: source, selected: ticker} = socket.assigns

    push_event(socket, "chart:data", %{
      ticker: ticker,
      interval: Candles.interval(source),
      candles: Candles.get(source, ticker)
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lg:flex lg:min-h-screen">
      <aside
        id="sidebar"
        class="border-b border-zinc-200 bg-zinc-50 p-4 lg:sticky lg:top-0 lg:h-screen lg:w-80 lg:shrink-0 lg:overflow-y-auto lg:border-r lg:border-b-0 dark:border-zinc-800 dark:bg-zinc-900/60"
      >
        <a href={~p"/prices"} class="text-xl font-bold tracking-tight">Capstock</a>
        <p class="text-xs text-zinc-500 dark:text-zinc-400">Paper trading, real prices</p>

        <.portfolio_card
          portfolio={@portfolio}
          prices={@prices}
          source={@source}
        />

        <h2 class="mt-6 text-xs font-semibold tracking-wider text-zinc-500 uppercase dark:text-zinc-400">
          Exit strategies
        </h2>
        <p class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
          <.rich text="A [[limit-entry|limit entry]] with its [[exit|exits]] set in advance. Open one to learn it and place it." />
        </p>
        <div id="exit-panels" class="mt-2 space-y-2">
          <.exit_panel
            :for={panel <- @panels}
            panel={panel}
            open={@open_panel == panel.id}
            form={@exit_form}
            selected={@selected}
            prices={@prices}
            portfolio={@portfolio}
          />
        </div>
      </aside>

      <main class="min-w-0 flex-1 p-4 lg:p-6">
        <header class="flex flex-wrap items-center gap-3 pr-28">
          <h1 class="text-2xl font-semibold">Live Prices</h1>
          <nav class="flex rounded-lg border border-zinc-300 p-0.5 text-sm dark:border-zinc-700">
            <a
              href={~p"/prices"}
              class={["rounded-md px-3 py-1", @source == :live && "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900"]}
            >
              Live
            </a>
            <a
              href={~p"/prices?source=mock"}
              class={["rounded-md px-3 py-1", @source == :mock && "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900"]}
            >
              Mock
            </a>
          </nav>
          <button
            id="help-button"
            type="button"
            phx-click={JS.toggle(to: "#help-panel")}
            class="rounded-full border border-zinc-300 px-3 py-1 text-sm hover:bg-zinc-100 dark:border-zinc-700 dark:hover:bg-zinc-800"
            aria-controls="help-panel"
          >
            ⓘ How paper trading works
          </button>
          <%!-- The hint for Space Space; a click opens the glossary too (no round trip). --%>
          <button
            id="glossary-button"
            type="button"
            phx-click={JS.dispatch("glossary:open", to: "#glossary")}
            class="flex items-center gap-1.5 rounded-full border border-zinc-300 px-3 py-1 text-sm hover:bg-zinc-100 dark:border-zinc-700 dark:hover:bg-zinc-800"
            title="Trading words explained. Press Space twice to open, Esc to close."
          >
            Glossary
            <span class="flex gap-0.5 text-[10px] text-zinc-500 dark:text-zinc-400">
              <kbd class="rounded border border-zinc-300 px-1 dark:border-zinc-700">Space</kbd>
              <span aria-hidden="true">+</span>
              <kbd class="rounded border border-zinc-300 px-1 dark:border-zinc-700">Space</kbd>
            </span>
          </button>
        </header>
        <p class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
          Source: {if @source == :mock, do: "mock stream (simulated)", else: "live market data"}
          <span :if={@source == :live and not @market_open} class="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-xs text-amber-800 dark:bg-amber-900/40 dark:text-amber-300">
            <.rich text="[[market-hours|Market closed]]: live orders wait for 9:30 ET. Mock prices trade any time." />
          </span>
        </p>

        <p
          :if={@message}
          id="order-message"
          class={[
            "mt-3 rounded-lg px-3 py-2 text-sm font-medium",
            if(elem(@message, 0) == :ok,
              do: "bg-emerald-50 text-emerald-800 dark:bg-emerald-950/50 dark:text-emerald-300",
              else: "bg-rose-50 text-rose-800 dark:bg-rose-950/50 dark:text-rose-300"
            )
          ]}
        >
          {elem(@message, 1)}
          <button
            :if={@undo}
            id="undo-button"
            type="button"
            phx-click="undo"
            class="ml-2 font-semibold underline underline-offset-2 hover:no-underline"
          >
            Undo
          </button>
        </p>

        <div class="mt-4 grid gap-4 xl:grid-cols-3">
          <section class="rounded-xl border border-zinc-200 p-3 xl:col-span-2 dark:border-zinc-800">
            <div class="flex items-baseline gap-2">
              <span class="text-lg font-semibold">{@selected}</span>
              <span class="truncate text-sm text-zinc-500 dark:text-zinc-400">{Tickers.name(@selected)}</span>
              <span id="chart-price" class="ml-auto font-semibold tabular-nums">
                {price_text(@prices[@selected])}
              </span>
              <%!-- Back to the automatic view after panning/zooming. Runs in the browser:
                   JS.dispatch fires a DOM event the Chart hook listens for, no server round trip. --%>
              <button
                id="chart-reset"
                type="button"
                phx-click={JS.dispatch("chart:reset", to: "#chart")}
                title="Reset the chart to the automatic view (fit all candles, auto-scale prices)"
                class="btn-outline self-center"
              >
                ⟲ Reset view
              </button>
            </div>
            <p class="text-xs text-zinc-500 dark:text-zinc-400">
              <.rich text={chart_caption(@source)} /> · times in <.time_zone id="tz-chart" />
            </p>
            <%!-- The hook owns everything inside (phx-update="ignore"): LiveView sends data as
                 events, the chart library draws it. --%>
            <div id="chart" phx-hook="Chart" phx-update="ignore" class="mt-2 h-64 w-full"></div>
          </section>

          <section id="trade" class="rounded-xl border border-zinc-200 p-3 dark:border-zinc-800">
            <h2 class="font-semibold">Trade</h2>
            <p class="text-xs text-zinc-500 dark:text-zinc-400">
              <.rich text="[[paper-trading|Paper trading]]: [[market-order|market orders]] fill at the price shown." />
            </p>

            <.ticker_chip id="trade-ticker" selected={@selected} prices={@prices} />

            <%!-- The benchmark form. The ticker comes from the watchlist selection instead of a
                 dropdown, but it's still submitted as a "ticker" field, so the event and the server
                 code are exactly what React's panel uses (LOG.md, 2026-11-07 evening). --%>
            <form id="order-form" phx-submit="order" phx-change="order_form" class="mt-3 flex flex-wrap items-end gap-2">
              <input type="hidden" name="ticker" value={@selected} />
              <.qty_input value={@order_form["quantity"]} jump="b" />
              <button type="submit" name="side" value="buy" disabled={not can_trade?(@portfolio, @prices, @selected)} class="btn bg-emerald-600">
                Buy {@selected}
              </button>
              <button type="submit" name="side" value="sell" disabled={not can_trade?(@portfolio, @prices, @selected)} class="btn bg-rose-600">
                Sell {@selected}
              </button>
            </form>

            <%!-- LiveView only. Kept out of #order-form so the benchmark panel stays identical to React's. --%>
            <form id="short-form" phx-submit="order" phx-change="short_form" class="mt-4 flex flex-wrap items-end gap-2">
              <span class="w-full text-sm font-semibold">Short selling</span>
              <input type="hidden" name="ticker" value={@selected} />
              <.qty_input value={@short_form["quantity"]} jump="s" />
              <button type="submit" name="side" value="short" disabled={not can_trade?(@portfolio, @prices, @selected)} class="btn bg-amber-600">
                Short {@selected}
              </button>
              <button type="submit" name="side" value="cover" disabled={not can_trade?(@portfolio, @prices, @selected)} class="btn bg-violet-600">
                Cover {@selected}
              </button>
              <span class="w-full text-xs text-zinc-500 dark:text-zinc-400">
                <.rich text="[[short|Short]] sells shares you don't own and profits if the price falls; [[cover|Cover]] buys them back. The short's full value is [[cash-secured-short|set aside]] from cash until you cover." />
              </span>
            </form>
          </section>
        </div>

        <div class="mt-4 grid gap-4 xl:grid-cols-5">
          <section class="rounded-xl border border-zinc-200 xl:col-span-2 dark:border-zinc-800">
            <h2 class="flex items-baseline justify-between px-3 pt-3 font-semibold">
              Watchlist
              <span id="watchlist-count" class="text-xs font-normal text-zinc-500 dark:text-zinc-400">
                {length(@tickers)} tickers · click to chart
              </span>
            </h2>
            <%!-- The Flash hook (app.js) owns this box: the input and a <style> it rewrites to hide,
                 sort and label the rows. phx-update="ignore" keeps LiveView from resetting either. --%>
            <div id="watchlist-filter" phx-hook="Flash" phx-update="ignore" class="px-3 pt-2">
              <label class="relative block">
                <span class="sr-only">Filter tickers</span>
                <input
                  type="search"
                  placeholder="Filter by ticker or name"
                  autocomplete="off"
                  spellcheck="false"
                  data-flash-input
                  class="input w-full pr-8"
                />
                <kbd class="pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 rounded border border-zinc-300 px-1 text-[10px] text-zinc-500 dark:border-zinc-700">
                  /
                </kbd>
              </label>
              <style data-flash-style></style>
            </div>
            <div class="mt-2 max-h-[28rem] overflow-y-auto">
              <%!-- Divs, not a <table>: the Flash hook sorts matches with CSS `order`, which only
                   works on flex items. The roles keep it a table for screen readers. --%>
              <div id="prices" role="table" aria-label="Watchlist" class="text-sm">
                <div
                  role="row"
                  class="sticky top-0 z-10 grid grid-cols-[1fr_auto_6.5rem] bg-white text-xs text-zinc-500 dark:bg-zinc-950 dark:text-zinc-400"
                >
                  <span role="columnheader" class="px-3 py-1.5">Ticker</span>
                  <span role="columnheader" class="px-2 py-1.5 text-right">Price</span>
                  <span role="columnheader" class="px-2 py-1.5 text-right">
                    Updated <.time_zone id="tz-watchlist" />
                  </span>
                </div>
                <div id="watchlist-rows" role="rowgroup" class="flex flex-col">
                  <%!-- :key lets LiveView 1.2 send only the rows that changed on a tick. --%>
                  <div
                    :for={t <- @tickers}
                    :key={t}
                    id={"price-#{t}"}
                    role="row"
                    data-ticker={t}
                    data-name={Tickers.name(t)}
                    phx-click="select_ticker"
                    phx-value-ticker={t}
                    class={[
                      "grid cursor-pointer grid-cols-[1fr_auto_6.5rem] items-center border-t border-zinc-100 hover:bg-zinc-50 dark:border-zinc-800 dark:hover:bg-zinc-900",
                      t == @selected && "bg-sky-50 dark:bg-sky-950/40"
                    ]}
                  >
                    <span role="cell" class="flex min-w-0 items-center gap-2 px-3 py-1.5">
                      <%!-- Empty and hidden until the Flash hook's stylesheet gives it a letter. --%>
                      <span class="flash-label" aria-hidden="true"></span>
                      <span class="min-w-0">
                        <span class="font-medium">{t}</span>
                        <span class="block truncate text-xs text-zinc-500 dark:text-zinc-400">{Tickers.name(t)}</span>
                      </span>
                    </span>
                    <span role="cell" class={["px-2 py-1.5 text-right whitespace-nowrap tabular-nums", direction_class(@prices[t])]}>
                      {price_text(@prices[t])}{arrow(@prices[t])}
                    </span>
                    <span role="cell" class="px-2 py-1.5 text-right text-xs whitespace-nowrap tabular-nums text-zinc-500 dark:text-zinc-400">
                      <.local_time :if={@prices[t]} id={"price-time-#{t}"} at={@prices[t].timestamp} />
                    </span>
                  </div>
                </div>
                <p id="watchlist-empty" class="hidden px-3 py-4 text-sm text-zinc-500 dark:text-zinc-400">
                  No ticker matches. Esc clears the filter.
                </p>
              </div>
            </div>
          </section>

          <%!-- Three panels in the space one used to take. On wide screens the wrapper is
               "h-0 min-h-full": it takes the row's height from the watchlist without adding to it,
               so each panel scrolls inside instead of stretching the page. --%>
          <div class="grid gap-4 xl:col-span-3 xl:h-0 xl:min-h-full xl:grid-cols-2 xl:grid-rows-2">
            <section id="positions-panel" class="panel xl:col-span-2">
              <h2 class="flex items-baseline justify-between font-semibold">
                Positions
                <span :if={@portfolio} id="cash" class="text-sm font-normal">
                  Cash <span class="font-semibold tabular-nums">{format_cents(@portfolio.cash_cents)}</span>
                </span>
              </h2>
              <p :if={@portfolio == nil} class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">Connecting…</p>
              <p :if={@portfolio && @portfolio.positions == []} class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">
                <.rich text="No [[position|positions]]." />
              </p>
              <table :if={@portfolio && @portfolio.positions != []} id="positions" class="mt-1 w-full text-left text-sm">
                <thead class="border-b border-zinc-300 text-xs text-zinc-500 dark:border-zinc-700 dark:text-zinc-400">
                  <tr>
                    <th class="py-1.5"><.term id="ticker" /></th>
                    <th class="py-1.5 text-right"><.term id="share" label="Qty" /></th>
                    <th class="py-1.5 text-right"><.term id="avg-cost" /></th>
                    <th class="py-1.5 text-right">Price</th>
                    <th class="py-1.5 text-right"><.term id="p-l" /></th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={pos <- @portfolio.positions}
                    id={"position-#{pos.ticker}"}
                    class="border-b border-zinc-100 dark:border-zinc-800"
                  >
                    <td class="py-1.5 font-medium">{pos.ticker}</td>
                    <td class="py-1.5 text-right tabular-nums">
                      {pos.quantity}<span :if={pos.quantity < 0} class="ml-1 text-xs text-amber-600 dark:text-amber-400">short</span>
                    </td>
                    <td class="py-1.5 text-right tabular-nums">{format_cents(pos.avg_cost_cents)}</td>
                    <td class="py-1.5 text-right tabular-nums">{position_price(@prices, pos)}</td>
                    <td class="py-1.5 text-right tabular-nums">{position_pnl(@prices, pos)}</td>
                  </tr>
                </tbody>
              </table>
            </section>

            <section id="open-orders-panel" phx-hook="MoveKeys" class="panel">
              <h2 class="font-semibold">Open orders</h2>
              <p :if={@pending == []} class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">No open orders.</p>
              <%!-- One card per bracket (an entry's exits, which cancel each other: OCO), as a
                   small price ladder with the live price between the exits; then entries still
                   waiting to fill. --%>
              <div :if={@pending != []} id="open-orders" class="mt-2 space-y-2 text-sm tabular-nums">
                <%!-- Click a card to show it on the chart (focus_order); its buttons still do
                     their own thing, since LiveView runs the nearest phx-click only. --%>
                <div
                  :for={g <- @order_groups}
                  id={"order-group-#{g.id}"}
                  phx-click="focus_order"
                  phx-value-id={g.id}
                  title="Show on the chart"
                  class={[
                    "cursor-pointer rounded-lg border border-l-4 border-zinc-200 p-2 hover:bg-zinc-50 dark:border-zinc-700 dark:hover:bg-zinc-900",
                    group_edge(g),
                    @focused == g.id && "ring-2 ring-sky-400 dark:ring-sky-500"
                  ]}
                >
                  <%= if g.kind == :bracket do %>
                    <div class="flex items-center gap-2 text-xs">
                      <span class={["font-semibold uppercase", direction_text(g.direction)]}>{g.direction}</span>
                      <span class="font-semibold">{g.quantity} {g.ticker}</span>
                      <span :if={g.entry_cents} class="text-zinc-500 dark:text-zinc-400">
                        filled at {format_cents(g.entry_cents)}
                      </span>
                      <span
                        :if={length(g.exits) == 2}
                        title="One-cancels-other: when one exit fills, the other is cancelled."
                        class="ml-auto rounded bg-zinc-100 px-1.5 py-0.5 text-[10px] font-semibold tracking-wide dark:bg-zinc-800"
                      >
                        OCO
                      </span>
                    </div>
                    <div class="mt-1 space-y-1">
                      <%= for item <- ladder(g.exits, current_cents(@prices, g.ticker)) do %>
                        <div :if={item == :now} class="flex items-center gap-2 text-[11px] text-zinc-500 dark:text-zinc-400">
                          <span class="h-px flex-1 border-t border-dashed border-zinc-300 dark:border-zinc-600"></span>
                          now {price_text(@prices[g.ticker])}
                          <span class="h-px flex-1 border-t border-dashed border-zinc-300 dark:border-zinc-600"></span>
                        </div>
                        <%!-- Label and text on one line; Move/Cancel stay together and wrap below
                             as a unit when the panel is narrow. --%>
                        <div :if={item != :now} id={"pending-#{item.id}"} class="flex flex-wrap items-center gap-x-2 gap-y-1">
                          <span class={["w-20 shrink-0 rounded px-1.5 py-0.5 text-center text-[11px] font-medium", exit_chip(item)]}>
                            {exit_name(item)}
                          </span>
                          <span class="whitespace-nowrap">{item.side} {item.quantity} at {format_cents(item.trigger_cents)}</span>
                          <div class="ml-auto flex items-center gap-1">
                          <%!-- Exits can be moved (e.g. a stop raised to break-even). --%>
                          <form id={"amend-#{item.id}"} phx-submit="amend_order" class="flex items-center gap-1">
                            <input type="hidden" name="order_id" value={item.id} />
                            <span class="relative block">
                              <input
                                type="number"
                                name="trigger"
                                min="0.01"
                                step="0.01"
                                required
                                placeholder={dollars(item.trigger_cents)}
                                aria-label="New price"
                                class="input num-input"
                              />
                              <%!-- Empty slot: the MoveKeys hook gives a letter (and the input's
                                   data-jump) only to Move boxes visible right now. --%>
                              <span class="jump-label jump-label-inside move-label" aria-hidden="true"></span>
                            </span>
                            <button type="submit" class="btn-outline">Move</button>
                          </form>
                          <button type="button" phx-click="cancel_order" phx-value-id={item.id} class="btn-outline">
                            Cancel
                          </button>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="text-xs font-semibold text-zinc-500 dark:text-zinc-400">Waiting entry</div>
                    <div id={"pending-#{g.order.id}"} class="mt-1 flex flex-wrap items-center gap-2">
                      <span class="min-w-0 flex-1">{Trading.describe(g.order)}</span>
                      <button type="button" phx-click="cancel_order" phx-value-id={g.order.id} class="btn-outline">
                        Cancel
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            </section>

            <section id="history-panel" class="panel">
              <h2 class="font-semibold">Order history</h2>
              <p :if={@orders == []} class="mt-1 text-sm text-zinc-500 dark:text-zinc-400">No orders yet.</p>
              <ul :if={@orders != []} id="orders" class="mt-1 space-y-1 text-sm tabular-nums">
                <li :for={order <- @orders} id={"order-#{order.id}"}>
                  <.local_time id={"order-time-#{order.id}"} at={order.inserted_at} /> {String.upcase(order.side)} {order.quantity} {order.ticker}
                  @ {format_cents(order.price_cents)} ({format_cents(order.total_cents)})
                  <%!-- How it was placed: a manual click, or which resting order filled it. --%>
                  <span class={["ml-1 rounded px-1.5 py-0.5 text-[11px] font-medium whitespace-nowrap", via_chip(order.via)]}>
                    {via_name(order.via)}
                  </span>
                </li>
              </ul>
            </section>
          </div>
        </div>
      </main>

      <.help_panel source={@source} />
      <.glossary />
    </div>
    """
  end

  # --- Components ---

  attr :portfolio, :any, required: true
  attr :prices, :map, required: true
  attr :source, :atom, required: true

  defp portfolio_card(assigns) do
    ~H"""
    <section
      id="save-file"
      phx-hook="SaveFile"
      data-source={@source}
      class="mt-4 rounded-xl border border-zinc-200 bg-white p-3 dark:border-zinc-800 dark:bg-zinc-950"
    >
      <h2 class="text-xs font-semibold tracking-wider text-zinc-500 uppercase dark:text-zinc-400">
        Your portfolio ({if @source == :mock, do: "mock", else: "live"})
      </h2>
      <p :if={@portfolio == nil} class="mt-2 text-sm text-zinc-500 dark:text-zinc-400">Connecting…</p>
      <div :if={@portfolio} id="account" class="mt-1">
        <p class="text-2xl font-semibold tabular-nums">{format_cents(account_value(@portfolio, @prices))}</p>
        <p class="text-sm tabular-nums">
          <span class={pnl_class(total_pnl(@portfolio, @prices))}>
            {format_signed_cents(total_pnl(@portfolio, @prices))} ({pnl_percent(@portfolio, @prices)})
          </span>
          <span class="text-zinc-500 dark:text-zinc-400">
            since start ({format_cents(Trading.starting_cash(@portfolio))})
          </span>
        </p>
      </div>

      <p class="mt-2 text-xs text-zinc-500 dark:text-zinc-400">
        Private to this tab and autosaved in this browser. Download the save file to keep it.
      </p>
      <div class="mt-2 flex flex-wrap gap-2">
        <button type="button" data-action="download" class="btn-outline" disabled={@portfolio == nil}>
          ⤓ Download save
        </button>
        <label class="btn-outline cursor-pointer">
          ⤒ Import save <input type="file" accept=".json,application/json" data-action="import" class="hidden" />
        </label>
      </div>

      <form id="new-portfolio" phx-submit="new_portfolio" class="mt-3 flex items-end gap-2">
        <label class="relative flex flex-1 flex-col text-xs">
          New portfolio, buying power $
          <span class="relative mt-1 block">
            <input
              type="number"
              name="starting_cash"
              value="100000"
              min="1000"
              max="2000000"
              step="1000"
              required
              data-jump="n"
              class="input w-full"
            />
            <.jump_label key="n" />
          </span>
        </label>
        <button
          type="submit"
          class="btn bg-zinc-800 dark:bg-zinc-200 dark:text-zinc-900"
        >
          Start
        </button>
      </form>
      <p class="mt-1 text-xs text-zinc-500 dark:text-zinc-400">$1,000 to $2,000,000.</p>
    </section>
    """
  end

  attr :panel, :map, required: true
  attr :open, :boolean, required: true
  attr :form, :map, required: true
  attr :selected, :string, required: true
  attr :prices, :map, required: true
  attr :portfolio, :any, required: true

  defp exit_panel(assigns) do
    ~H"""
    <div id={"panel-#{@panel.id}"} class="relative rounded-xl border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-950">
      <%!-- A closed panel has a jump key that opens it; the open one has none (nothing to do). --%>
      <.jump_label :if={not @open} key={@panel.jump} placement="corner" />
      <button
        type="button"
        phx-click="toggle_panel"
        phx-value-panel={@panel.id}
        aria-expanded={to_string(@open)}
        data-jump={if not @open, do: @panel.jump}
        class="flex w-full items-center justify-between px-3 py-2 text-left text-sm font-semibold"
      >
        <span>
          <span class={["mr-1 inline-block w-3", if(@open, do: "rotate-90", else: "")]}>▸</span>
          {@panel.title}
        </span>
        <span class={[
          "rounded px-1.5 py-0.5 text-[10px] font-medium uppercase",
          if(@panel.direction == "long",
            do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-300",
            else: "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300"
          )
        ]}>
          {@panel.direction}
        </span>
      </button>

      <div :if={@open} class="border-t border-zinc-100 px-3 pt-2 pb-3 text-sm dark:border-zinc-800">
        <dl class="space-y-1.5 text-xs leading-relaxed">
          <div :for={{label, text} <- tutorial(@panel.id)}>
            <dt class="inline font-semibold">{label}:</dt>
            <dd class="inline text-zinc-600 dark:text-zinc-300"><.rich text={text} /></dd>
          </div>
        </dl>

        <form id={"exit-form-#{@panel.id}"} phx-submit="limit_order" phx-change="exit_form" class="mt-3 grid grid-cols-2 gap-2">
          <input type="hidden" name="direction" value={@panel.direction} />
          <input type="hidden" name="ticker" value={@selected} />
          <div class="col-span-2">
            <.ticker_chip id={"exit-ticker-#{@panel.id}"} selected={@selected} prices={@prices} />
          </div>
          <.qty_input value={@form["quantity"]} jump="q" />
          <.price_input name="limit" label="Entry (limit) $" value={@form["limit"]} jump="e" required />
          <.price_input
            name="stop"
            label={if @panel.exit == :stop, do: "Stop-loss $", else: "Stop-loss $ (optional)"}
            value={@form["stop"]}
            jump="x"
            required={@panel.exit == :stop}
          />
          <.price_input
            name="take_profit"
            label={if @panel.exit == :take_profit, do: "Take-profit $", else: "Take-profit $ (opt.)"}
            value={@form["take_profit"]}
            jump="t"
            required={@panel.exit == :take_profit}
          />
          <div class="flex items-end">
            <button type="button" phx-click="suggest" phx-value-panel={@panel.id} class="btn-outline w-full">
              Example prices
            </button>
          </div>
          <p class="col-span-2 text-xs tabular-nums text-zinc-600 dark:text-zinc-300">
            <.rich text={risk_preview(@form, @panel.direction, @portfolio, @prices)} />
          </p>
          <button
            type="submit"
            disabled={not can_trade?(@portfolio, @prices, @selected)}
            class={["btn col-span-2", if(@panel.direction == "long", do: "bg-emerald-600", else: "bg-amber-600")]}
          >
            Place {@panel.direction} entry · {@selected}
          </button>
        </form>
      </div>
    </div>
    """
  end

  attr :source, :atom, required: true

  # Not modal: no backdrop, the page stays usable behind it, and it closes with ✕ or the same
  # button. Toggled in the browser with JS commands (no server round trip); LiveView keeps the
  # shown/hidden state across patches.
  defp help_panel(assigns) do
    ~H"""
    <aside
      id="help-panel"
      role="dialog"
      aria-label="How paper trading works"
      class="fixed right-4 bottom-4 z-20 hidden max-h-[80vh] w-[min(26rem,calc(100vw-2rem))] overflow-y-auto rounded-xl border border-zinc-200 bg-white p-4 text-sm shadow-xl dark:border-zinc-700 dark:bg-zinc-900"
    >
      <div class="flex items-start justify-between">
        <h2 class="font-semibold">How paper trading works</h2>
        <button
          type="button"
          phx-click={JS.hide(to: "#help-panel")}
          aria-label="Close"
          class="rounded px-1.5 text-zinc-500 hover:bg-zinc-100 dark:hover:bg-zinc-800"
        >
          ✕
        </button>
      </div>
      <div class="mt-2 space-y-2 text-zinc-700 dark:text-zinc-300">
        <p>
          <strong>Fake money, real prices.</strong>
          <.rich text="You trade a simulated portfolio ([[paper-trading|paper trading]]), so you can test a strategy and find out whether it works before risking real money. Most [[day-trading|day traders]] lose money; a record of practice trades shows whether your results are skill or luck." />
        </p>
        <p>
          <strong>Prices.</strong>
          <.rich text="Live: 5 [[ticker|tickers]] from Finnhub and 45 from Alpaca's free [[iex|IEX]] feed (real trades on one US exchange, so within a cent or so of the full market). Live orders only fill [[market-hours|9:30–16:00 ET]] on trading days. Mock: simulated prices that move around the clock, for practice any time." />
        </p>
        <p>
          <strong>Orders.</strong>
          <.rich text="Buy/Sell [[fill]] now at the price shown. [[short|Short]] sells shares you don't own, betting the price falls; [[cover|Cover]] buys them back. A [[limit-entry|limit entry]] waits for a better price. A [[stop-loss]] closes the [[position]] if the price moves against you; a [[take-profit]] closes it at your target. When one exit fills, the other is cancelled ([[oco|OCO]])." />
        </p>
        <p>
          <strong>Your portfolio is yours.</strong>
          It exists only in this tab while it's open; nobody else can see or change it, and there's no
          account. Every change is autosaved in this browser, so a reload picks up where you left off.
          Download the save file to keep it or move it to another browser, and Import it to resume.
          The file is readable but signed, so an edited file won't load.
        </p>
        <p>
          <strong>Keyboard.</strong>
          <kbd>/</kbd> searches the watchlist; press the letter next to a result to pick it. When you're
          not typing, every number box shows a small key at its right end, like the
          <kbd>/</kbd> in the search box: press that letter to jump there. The closed exit
          strategies show one too (<kbd>a</kbd> <kbd>d</kbd> <kbd>f</kbd> <kbd>g</kbd>): press it to
          open that panel. <kbd>Esc</kbd> leaves a box. Enter never places an order: order buttons
          always take a click. <kbd>Space</kbd> <kbd>Space</kbd> opens the glossary of trading words.
        </p>
        <p>
          <strong>One limit.</strong>
          Stop-losses and take-profits are watched only while this tab is open. Close it and they wait
          until you come back.
        </p>
      </div>
    </aside>
    """
  end

  # Glossary terms in the page's own text (2026-11-08). A term has a dotted underline in the
  # normal text colour (colour already means buy/sell, P/L, take-profit and stop-loss here, and a
  # coloured word reads as a link). Hovering or focusing it shows its one-line definition, and a
  # click opens the glossary at that term (both in app.js). Only explanatory text is marked, once
  # per block, and never inside a button or label: a click on "Buy" must only buy.
  #
  # Terms are plain <button type="button"> elements, so the keyboard reaches them and a click
  # inside a form never submits it. The markup is built as a string rather than HEEx, so no
  # formatter-added whitespace can sneak in between a term and the punctuation after it.
  attr :id, :string, required: true
  attr :label, :string, default: nil

  defp term(assigns) do
    ~H"{Phoenix.HTML.raw(term_iodata(@id, @label || Glossary.fetch!(@id).term))}"
  end

  # Text with glossary markers: "Set an [[entry]] that [[fill|fills]]." (Glossary.split_marked/1).
  attr :text, :string, required: true

  defp rich(assigns) do
    ~H"{rich_html(@text)}"
  end

  defp rich_html(text) do
    text
    |> Glossary.split_marked()
    |> Enum.map(fn
      {:term, id, label} -> term_iodata(id, label)
      part -> escape_html(part)
    end)
    |> Phoenix.HTML.raw()
  end

  defp term_iodata(id, label) do
    t = Glossary.fetch!(id)

    [
      ~s(<button type="button" class="term" data-term-link="),
      escape_html(t.id),
      ~s(" data-term-name="),
      escape_html(t.term),
      ~s(" data-term-short="),
      escape_html(t.short),
      ~s(">),
      escape_html(label),
      "</button>"
    ]
  end

  defp escape_html(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # Glossary popup (2026-11-08): trading words for people who don't trade. Space Space opens it
  # (or the header button), Esc closes it. It has no state on purpose: every open starts from
  # the same blank filter and intro, whatever term was showing when it closed.
  #
  # All in the browser. The terms are rendered once (the component takes no assigns, so
  # LiveView never re-renders it) and phx-update="ignore" keeps patches out, so the Glossary
  # hook in app.js can show, hide and reorder rows directly. Opening it costs no round trip and
  # no server memory beyond the first render. The filter and its labels are the watchlist's
  # flash.nvim rules (flash.js), except that Backspace clears the whole filter at once.
  defp glossary(assigns) do
    assigns = assign(assigns, :terms, Glossary.terms())

    ~H"""
    <div id="glossary" phx-hook="Glossary" phx-update="ignore">
      <div
        data-glossary-panel
        role="dialog"
        aria-modal="true"
        aria-label="Glossary"
        class="fixed inset-0 z-50 hidden"
      >
        <div data-glossary-backdrop class="absolute inset-0 bg-zinc-950/30 backdrop-blur-sm"></div>
        <div class="relative mx-auto mt-[6vh] flex h-[min(88vh,44rem)] w-[min(56rem,calc(100vw-2rem))] flex-col overflow-hidden rounded-xl border border-zinc-200 bg-white text-sm shadow-2xl dark:border-zinc-700 dark:bg-zinc-900">
          <div class="flex flex-wrap items-center gap-3 border-b border-zinc-200 p-3 dark:border-zinc-800">
            <h2 class="font-semibold">Glossary</h2>
            <label class="relative min-w-40 flex-1">
              <span class="sr-only">Filter terms</span>
              <input
                type="search"
                data-glossary-input
                placeholder="Filter, e.g. stop or rr"
                autocomplete="off"
                spellcheck="false"
                class="input w-full pr-28"
              />
              <span class="pointer-events-none absolute top-1/2 right-2 -translate-y-1/2 text-[10px] text-zinc-500">
                <kbd class="rounded border border-zinc-300 px-1 dark:border-zinc-700">Backspace</kbd> clears
              </span>
            </label>
            <span data-glossary-count class="text-xs text-zinc-500 dark:text-zinc-400">
              {length(@terms)} terms
            </span>
            <span class="text-xs text-zinc-500 dark:text-zinc-400">
              <kbd class="rounded border border-zinc-300 px-1 dark:border-zinc-700">Esc</kbd> closes
            </span>
          </div>
          <div class="flex min-h-0 flex-1 flex-col sm:flex-row">
            <ul
              data-glossary-list
              class="flex max-h-[30vh] shrink-0 flex-col overflow-y-auto border-b border-zinc-200 py-1 sm:max-h-none sm:w-72 sm:border-r sm:border-b-0 dark:border-zinc-800"
            >
              <li
                :for={t <- @terms}
                id={"glossary-#{t.id}"}
                data-term-id={t.id}
                data-term={t.term}
                data-aliases={Enum.join(t.aliases, " / ")}
              >
                <button
                  type="button"
                  tabindex="-1"
                  class="flex w-full items-start gap-2 px-3 py-1.5 text-left hover:bg-zinc-100 dark:hover:bg-zinc-800"
                >
                  <span class="flash-label mt-0.5" aria-hidden="true"></span>
                  <span class="min-w-0">
                    <span class="block font-medium">{t.term}</span>
                    <span class="block truncate text-xs text-zinc-500 dark:text-zinc-400">{t.short}</span>
                  </span>
                </button>
              </li>
              <li data-glossary-empty hidden class="px-3 py-2 text-zinc-500">
                No term matches. <kbd class="rounded border border-zinc-300 px-1 dark:border-zinc-700">Backspace</kbd>
                clears the filter.
              </li>
            </ul>
            <div data-glossary-detail class="min-h-0 flex-1 overflow-y-auto p-4">
              <div data-glossary-intro class="space-y-2 text-zinc-700 dark:text-zinc-300">
                <p class="font-medium">Trading words, in plain English.</p>
                <p>
                  Type to filter, like the watchlist search: a letter appears next to each match,
                  and pressing it opens that term. <kbd>Enter</kbd> opens the best match,
                  <kbd>Backspace</kbd> clears the filter, and <kbd>Esc</kbd> closes the glossary. You can also
                  click a term.
                </p>
                <p class="text-zinc-500 dark:text-zinc-400">
                  New to trading? Start with Long, Short, Position, Stop-loss and Take-profit.
                </p>
              </div>
              <article :for={t <- @terms} data-detail={t.id} hidden class="space-y-3">
                <div>
                  <h3 class="text-lg font-semibold">{t.term}</h3>
                  <p :if={t.aliases != []} class="text-xs text-zinc-500 dark:text-zinc-400">
                    Also: {Enum.join(t.aliases, ", ")}
                  </p>
                </div>
                <p class="font-medium">{t.short}</p>
                <p class="text-zinc-700 dark:text-zinc-300">{t.body}</p>
                <p
                  :if={t.in_app}
                  class="rounded-lg bg-sky-50 px-3 py-2 text-sky-900 dark:bg-sky-950/40 dark:text-sky-200"
                >
                  <span class="font-semibold">In Capstock:</span> {t.in_app}
                </p>
                <div :if={t.related != []} class="flex flex-wrap items-center gap-1.5">
                  <span class="text-xs text-zinc-500 dark:text-zinc-400">Related:</span>
                  <button
                    :for={rel <- t.related}
                    type="button"
                    tabindex="-1"
                    data-goto={rel}
                    class="rounded-full border border-zinc-300 px-2 py-0.5 text-xs hover:border-sky-400 dark:border-zinc-700"
                  >
                    {Glossary.get(rel).term}
                  </button>
                </div>
              </article>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :selected, :string, required: true
  attr :prices, :map, required: true

  # What the forms will trade, in place of a ticker dropdown (2026-11-07): the watchlist's
  # selection, with its name and live price. Clicking it focuses the watchlist filter (in the
  # browser, no round trip), the same as pressing "/". The inner span's id includes the ticker,
  # so a new selection is a new element and its highlight animation plays: a misclicked row is
  # noticed before trading.
  defp ticker_chip(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={JS.focus(to: "#watchlist-filter [data-flash-input]")}
      title="Trading this ticker. Pick another in the watchlist (press /)."
      class="mt-2 flex w-full items-center gap-2 rounded-lg border border-zinc-200 px-2.5 py-1.5 text-left hover:border-sky-400 dark:border-zinc-700"
    >
      <span id={"#{@id}-#{@selected}"} class="chip-flash flex min-w-0 flex-1 items-baseline gap-2 rounded">
        <span class="font-semibold">{@selected}</span>
        <span class="truncate text-xs text-zinc-500 dark:text-zinc-400">{Tickers.name(@selected)}</span>
        <span class={["ml-auto tabular-nums", direction_class(@prices[@selected])]}>
          {price_text(@prices[@selected])}
        </span>
      </span>
      <span class="shrink-0 text-[10px] text-zinc-500 dark:text-zinc-400">
        change <kbd class="rounded border border-zinc-300 px-1 dark:border-zinc-700">/</kbd>
      </span>
    </button>
    """
  end

  # Buttons are disabled until there's a portfolio and the selected ticker has a price.
  defp can_trade?(portfolio, prices, selected), do: portfolio != nil and prices[selected] != nil

  # Jump keys (2026-11-07): every number input has a letter. When you're not typing, a small
  # label shows it; pressing the letter focuses that input and selects its value, Esc leaves.
  # Buttons have no key on purpose: placing an order always takes a click. The one exception is
  # the four exit-panel headers (a d f g): opening a panel never trades, so a key "clicks" it. The labels and
  # `data-jump` are rendered here; app.js only listens for keys and toggles `data-jump-on` on
  # <html> (outside LiveView, so patches never undo it).
  #
  # Fixed letters for fixed inputs, so they become muscle memory: b = Buy/Sell quantity,
  # s = Short quantity, q/e/x/t = exit panel quantity/entry/stop-loss (x: cut it)/take-profit
  # (only one panel is open, so they never clash), n = new portfolio, a/d/f/g = the closed exit
  # panels. The Move boxes in Open orders get theirs in the browser (MoveKeys hook in app.js),
  # only while visible, so a long list never runs out of letters. No "l" or "i": in many fonts
  # they look alike (or like 1).

  attr :key, :string, default: nil
  # "inside": in the input's right end, like the watchlist filter's [/] (put it right after the
  # input, in a `relative` wrapper). "corner": on a panel header's top-right corner.
  attr :placement, :string, default: "inside"

  defp jump_label(assigns) do
    ~H"""
    <span :if={@key} class={["jump-label", "jump-label-#{@placement}"]} aria-hidden="true">{@key}</span>
    """
  end

  # A bracket's exits, highest price first, with :now where the live price falls between them.
  # Exits always straddle the price (one past it would have filled), so :now lands in the middle;
  # with no price yet there's no marker.
  defp ladder(exits, nil), do: exits

  defp ladder(exits, now_cents) do
    {above, below} = Enum.split_with(exits, &(&1.trigger_cents >= now_cents))
    above ++ [:now | below]
  end

  defp via_name("stop_loss"), do: "stop-loss"
  defp via_name("take_profit"), do: "take-profit"
  defp via_name("limit_entry"), do: "limit entry"
  # "manual", or nil on orders from before the column existed.
  defp via_name(_manual), do: "manual"

  # Same colours as the Open orders chips and chart lines; a limit entry is neutral grey.
  defp via_chip("stop_loss"), do: exit_chip(%{type: "stop"})
  defp via_chip("take_profit"), do: exit_chip(%{type: "limit"})

  defp via_chip("limit_entry"),
    do: "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"

  # The most common tag, so the quietest: outlined, no fill.
  defp via_chip(_manual),
    do: "border border-zinc-300 text-zinc-500 dark:border-zinc-600 dark:text-zinc-400"

  defp exit_name(%{type: "stop"}), do: "Stop-loss"
  defp exit_name(_take_profit), do: "Take-profit"

  # Blue take-profit, orange stop-loss: the chart's dotted lines use the same colours
  # (@line_colors). Green and red already mean up/down candles and buy/sell.
  defp exit_chip(%{type: "stop"}),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-300"

  defp exit_chip(_take_profit),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300"

  defp group_edge(%{kind: :bracket, direction: :long}), do: "border-l-emerald-500"
  defp group_edge(%{kind: :bracket, direction: :short}), do: "border-l-amber-500"
  defp group_edge(_entry), do: "border-l-zinc-400 border-dashed"

  defp direction_text(:long), do: "text-emerald-700 dark:text-emerald-400"
  defp direction_text(:short), do: "text-amber-700 dark:text-amber-400"

  attr :value, :string, default: "1"
  attr :jump, :string, default: nil

  defp qty_input(assigns) do
    ~H"""
    <label class="flex flex-col text-xs">
      Quantity
      <span class="relative mt-1 block w-fit">
        <input
          type="number"
          name="quantity"
          value={@value}
          phx-debounce="250"
          min="1"
          step="1"
          data-jump={@jump}
          class="input num-input"
        />
        <.jump_label key={@jump} />
      </span>
    </label>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :required, :boolean, default: false
  attr :jump, :string, default: nil

  defp price_input(assigns) do
    ~H"""
    <label class="flex flex-col text-xs">
      {@label}
      <span class="relative mt-1 block w-fit">
        <input
          type="number"
          name={@name}
          value={@value}
          phx-debounce="250"
          min="0.01"
          step="0.01"
          required={@required}
          data-jump={@jump}
          class="input num-input"
        />
        <.jump_label key={@jump} />
      </span>
    </label>
    """
  end

  # A time shown in the viewer's own time zone. The server doesn't know that zone, so it renders
  # UTC (correct, just not local) and the LocalTime hook in app.js rewrites the text in the
  # browser with toLocaleTimeString, the same call the React panel uses. `datetime` carries the
  # exact instant; the hook re-runs whenever LiveView patches the element.
  attr :id, :string, required: true
  attr :at, :any, required: true

  defp local_time(assigns) do
    ~H"""
    <time id={@id} phx-hook="LocalTime" datetime={iso_utc(@at)} title="UTC">{format_time(@at)}</time>
    """
  end

  # --- Tutorials: what you're trying to achieve, how, and why ---

  defp tutorial("long_tp") do
    [
      {"Goal", "[[long|Buy]], then sell automatically once the price reaches your target."},
      {"How",
       "Set an [[entry]] below the current price; it [[fill|fills]] when the price dips below it. " <>
         "Set the [[take-profit]] above the entry. When the price trades above it, the shares sell " <>
         "at the take-profit."},
      {"Why",
       "You pick the [[exit]] while you're calm, not in the moment. John takes half off at the " <>
         "first opposing zone; sell part of the [[position]] and let the rest run."}
    ]
  end

  defp tutorial("long_sl") do
    [
      {"Goal", "[[long|Buy]], and cap the loss if the price falls instead."},
      {"How",
       "Set an [[entry]] below the current price and a [[stop]] below the entry. At the first " <>
         "price at or below the stop, the shares sell at that price (lower if the price " <>
         "[[gap|gaps]] down)."},
      {"Why",
       "Accept the loss before the order [[fill|fills]]. [[risk|Risk]] is (entry − stop) × " <>
         "shares; John keeps it near 7% of the [[position]]. Without a stop, one bad trade can " <>
         "wipe out many good ones."}
    ]
  end

  defp tutorial("short_tp") do
    [
      {"Goal", "Profit from a fall: [[short]] high, [[cover]] automatically at a lower target."},
      {"How",
       "Set an [[entry]] above the current price; the short opens when the price rises above " <>
         "it. Set the [[take-profit]] below the entry. When the price trades below it, the short " <>
         "is covered."},
      {"Why",
       "John's QBTS trade: short a parabolic run back into a supply zone, cover half at the " <>
         "next demand zone. The target is planned before the trade, not chased."}
    ]
  end

  defp tutorial("short_sl") do
    [
      {"Goal", "[[short|Short]], and cap the loss if the price rises instead."},
      {"How",
       "Set an [[entry]] above the current price and a [[stop]] above the entry, just past the " <>
         "swing high. At the first price at or above the stop, the short is [[cover|covered]] at " <>
         "that price."},
      {"Why",
       "A stock can rise without limit, so an unprotected short can lose more than it was worth. " <>
         "The stop turns an open-ended [[risk]] into a known one."}
    ]
  end

  # Risk, reward and risk-to-reward from the form, before placing (the pre-trade preview John
  # asked for in interview 1). Display only; the trading module validates the order itself.
  defp risk_preview(form, direction, portfolio, prices) do
    qty = parse_int(form["quantity"])
    entry = parse_cents(form["limit"])

    if qty && entry do
      sign = if direction == "long", do: 1, else: -1
      risk = per_share(entry, parse_cents(form["stop"]), sign) * qty
      reward = per_share(parse_cents(form["take_profit"]), entry, sign) * qty
      value = portfolio && account_value(portfolio, prices)

      [
        "[[position-size|Position]] #{format_cents(entry * qty)}"
        | risk_parts(risk, reward, value)
      ]
      |> Enum.join(" · ")
    else
      "Enter a quantity and entry to see the risk."
    end
  end

  # How far `from` is above `to` in the trade's favour, per share; 0 when a price is missing.
  defp per_share(nil, _to, _sign), do: 0
  defp per_share(_from, nil, _sign), do: 0
  defp per_share(from, to, sign), do: (from - to) * sign

  defp risk_parts(risk, reward, value) do
    [
      risk > 0 && "[[risk]] #{format_cents(risk)}" <> percent_of(risk, value),
      reward > 0 && "[[target]] #{format_cents(reward)}",
      (risk > 0 and reward > 0) &&
        "[[r-r|R:R]] 1:#{:erlang.float_to_binary(reward / risk, decimals: 1)}"
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp percent_of(_cents, nil), do: ""
  defp percent_of(_cents, value) when value <= 0, do: ""

  defp percent_of(cents, value),
    do: " (#{:erlang.float_to_binary(cents * 100 / value, decimals: 2)}% of account)"

  defp parse_int(text) when is_binary(text) do
    case Integer.parse(String.trim(text)) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp parse_cents(text) when is_binary(text) do
    case Float.parse(String.trim(text)) do
      {f, ""} when f > 0 -> round(f * 100)
      _ -> nil
    end
  end

  defp parse_cents(_), do: nil

  # --- Display helpers ---

  defp chart_caption(:live),
    do: "5-minute [[candlestick|candles]] (Alpaca [[sip|SIP]] history, then live ticks)"

  defp chart_caption(:mock), do: "1-minute [[candlestick|candles]] from the mock stream"

  defp account_value(portfolio, prices),
    do: Trading.account_value_cents(portfolio, &current_cents(prices, &1))

  defp total_pnl(portfolio, prices),
    do: account_value(portfolio, prices) - Trading.starting_cash(portfolio)

  defp pnl_percent(portfolio, prices) do
    pct = total_pnl(portfolio, prices) * 100 / Trading.starting_cash(portfolio)
    sign = if pct > 0, do: "+", else: ""
    sign <> :erlang.float_to_binary(pct, decimals: 2) <> "%"
  end

  defp pnl_class(cents) when cents > 0, do: "text-emerald-700 dark:text-emerald-400"
  defp pnl_class(cents) when cents < 0, do: "text-rose-700 dark:text-rose-400"
  defp pnl_class(_), do: ""

  defp price_text(nil), do: "–"
  defp price_text(%{price: price}), do: "$" <> format_price(price)

  defp arrow(%{price: p, prev: prev}) when is_number(prev) and p > prev, do: " ▲"
  defp arrow(%{price: p, prev: prev}) when is_number(prev) and p < prev, do: " ▼"
  defp arrow(_), do: ""

  defp direction_class(%{price: p, prev: prev}) when is_number(prev) and p > prev,
    do: "text-emerald-700 dark:text-emerald-400"

  defp direction_class(%{price: p, prev: prev}) when is_number(prev) and p < prev,
    do: "text-rose-700 dark:text-rose-400"

  defp direction_class(_), do: ""

  # Current price and unrealized P/L for a position, from the live prices on this page.
  # "–" when the ticker has no price yet.
  defp position_price(prices, pos) do
    case current_cents(prices, pos.ticker) do
      nil -> "–"
      cents -> format_cents(cents)
    end
  end

  defp position_pnl(prices, pos) do
    case current_cents(prices, pos.ticker) do
      nil -> "–"
      cents -> format_signed_cents((cents - pos.avg_cost_cents) * pos.quantity)
    end
  end

  # Display only: the trading module does its own exact conversion when an order fills.
  defp current_cents(prices, ticker) do
    case prices[ticker] do
      %{price: price} -> round(price * 100)
      nil -> nil
    end
  end

  # Integer cents -> "$1,234.56" (or "-$1,234.56").
  defp format_cents(cents), do: Trading.format_cents(cents)

  defp format_signed_cents(cents) when cents > 0, do: "+" <> format_cents(cents)
  defp format_signed_cents(cents), do: format_cents(cents)

  # Display only. Prices are floats here; the trading module converts to integer cents.
  defp format_price(price) when is_number(price),
    do: :erlang.float_to_binary(price / 1, decimals: 2)

  # The viewer's time-zone abbreviation (PST, CST, EST, or e.g. GMT+1 outside the US). The server
  # can't know it, so it renders "UTC", which is what the times say until JavaScript runs; the
  # TimeZone hook in app.js swaps in the browser's zone, with the full name as a tooltip.
  attr :id, :string, required: true

  defp time_zone(assigns) do
    ~H"""
    <abbr id={@id} phx-hook="TimeZone" title="Coordinated Universal Time" class="no-underline">UTC</abbr>
    """
  end

  # NaiveDateTime has no zone; ours are always UTC, so say so, or the browser would read the
  # string as local time and be off by the viewer's offset.
  defp iso_utc(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp iso_utc(%NaiveDateTime{} = at), do: NaiveDateTime.to_iso8601(at) <> "Z"

  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)

  defp unix(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  # Works for DateTime (DB rows, Mock.Streamer) and NaiveDateTime.
  defp format_time(%{} = timestamp), do: Calendar.strftime(timestamp, "%H:%M:%S")

  # 12345 -> "123.45", for an input's value or placeholder.
  defp dollars(cents), do: :erlang.float_to_binary(cents / 100, decimals: 2)
end
