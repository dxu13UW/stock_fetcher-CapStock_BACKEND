defmodule StockFetcherWeb.PricesLiveTest do
  # async: false: this module writes to SQLite, which has one write lock held by each test's
  # sandbox transaction until it ends; async writers time out with "Database busy".
  use StockFetcherWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StockFetcher.Trading

  # The price topics are global, so another test's broadcast could reach these LiveViews.
  # Each test uses a ZZ* ticker no other test uses and only asserts on it.

  test "renders the prices page", %{conn: conn} do
    # live/2 does both mounts: the HTTP render, then the connected (WebSocket) one.
    {:ok, _view, html} = live(conn, ~p"/prices")

    assert html =~ "Live Prices"
  end

  test "mount loads the latest prices from the DB", %{conn: conn} do
    # With rows in the DB, mount/3 runs the inserted_at -> timestamp conversion.
    # (An empty DB never calls the Map.new function, which hid a KeyError once.)
    {:ok, _} = StockFetcher.save_price("ZZTEST", 12.34)

    {:ok, view, html} = live(conn, ~p"/prices")

    assert html =~ "ZZTEST"
    assert has_element?(view, "#price-ZZTEST", "12.34")
  end

  test "a broadcast adds a row, and the next one updates it in place", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/prices")

    broadcast_price("ZZLIVE", 1.5)
    # render/1 is a call to the LiveView process. It is queued behind the broadcast (both
    # come from this test process), so the update has been handled when it returns.
    assert render(view) =~ "ZZLIVE"
    assert has_element?(view, "#price-ZZLIVE", "1.50")

    broadcast_price("ZZLIVE", 2.25)
    assert has_element?(view, "#price-ZZLIVE", "2.25")
    refute has_element?(view, "#price-ZZLIVE", "1.50")
  end

  test "?source=mock listens to stocks:mock, not stocks:live", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/prices?source=mock")
    assert html =~ "mock stream"

    broadcast_price("ZZMOCK", 3.5, "stocks:mock")
    broadcast_price("ZZREAL", 4.5, "stocks:live")

    assert has_element?(view, "#price-ZZMOCK", "3.50")
    refute has_element?(view, "#price-ZZREAL")
  end

  describe "trading panel" do
    # Each test broadcasts its own ZZ* ticker. Every tab gets a fresh $100,000 session
    # portfolio (no autosave in the connect params).

    test "shows cash, no positions and no orders at first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/prices?source=mock")

      assert has_element?(view, "#cash", "$100,000.00")
      assert render(view) =~ "No positions."
      assert render(view) =~ "No orders yet."
    end

    test "a buy fills at the shown price and updates cash, position and history", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZBUY", 10.0)

      submit_order(view, "ZZBUY", "3", "buy")

      assert has_element?(view, "#order-message", "Bought 3 ZZBUY at $10.00 ($30.00)")
      assert has_element?(view, "#cash", "$99,970.00")
      assert has_element?(view, "#position-ZZBUY", "3")
      assert has_element?(view, "#orders", "BUY 3 ZZBUY")
      # A manual market order gets no "via" tag.
      refute has_element?(view, "#orders li span", "limit entry")
      refute has_element?(view, "#orders li span", "stop-loss")
    end

    test "P/L follows the live price", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZPNL", 10.0)
      submit_order(view, "ZZPNL", "2", "buy")

      broadcast_price("ZZPNL", 12.5, "stocks:mock")

      assert has_element?(view, "#position-ZZPNL", "+$5.00")
    end

    test "insufficient cash shows the error and changes nothing", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZBIG", 500.0)

      submit_order(view, "ZZBIG", "1000", "buy")

      assert has_element?(view, "#order-message", "Insufficient cash for this order.")
      assert has_element?(view, "#cash", "$100,000.00")
      refute has_element?(view, "#position-ZZBIG")
    end

    test "selling more than held shows the error", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZSELL", 5.0)

      submit_order(view, "ZZSELL", "1", "sell")

      assert has_element?(view, "#order-message", "You can't sell more shares than you hold.")
    end

    test "a ticker with no price shows unknown ticker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/prices?source=mock")

      # The dropdown only lists priced tickers, so send the event directly, as a stale or
      # hand-made form would.
      render_submit(view, "order", %{"ticker" => "ZZNONE", "quantity" => "1", "side" => "buy"})

      assert has_element?(view, "#order-message", "Unknown ticker: no price available.")
    end

    test "after hours, live orders are rejected but mock orders still fill", %{conn: conn} do
      pin_clock(~U[2026-11-07 16:00:00Z])

      {:ok, live_view, _html} = live(conn, ~p"/prices")
      broadcast_price("ZZLIVE", 10.0)
      assert has_element?(live_view, "#price-ZZLIVE")
      submit_order(live_view, "ZZLIVE", "1", "buy")
      assert has_element?(live_view, "#order-message", Trading.error_message(:market_closed))
      refute has_element?(live_view, "#position-ZZLIVE")

      mock_view = mock_view_with_price(build_conn(), "ZZMOCK", 10.0)
      submit_order(mock_view, "ZZMOCK", "1", "buy")
      assert has_element?(mock_view, "#order-message", "Bought 1 ZZMOCK at $10.00 ($10.00)")
    end
  end

  describe "forms survive price ticks" do
    # Every tick re-renders the page. LiveView only protects the focused input, so the
    # server must remember what was typed (phx-change) or the next tick resets it.
    test "typed values and the selected ticker stay after a tick", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZA", 10.0)
      broadcast_price("ZZB", 20.0, "stocks:mock")
      select(view, "ZZB")

      view |> form("#order-form", %{quantity: "7"}) |> render_change()

      view
      |> form("#exit-form-long_sl", %{quantity: "3", limit: "19.5", stop: "18"})
      |> render_change()

      broadcast_price("ZZA", 11.0, "stocks:mock")
      assert has_element?(view, "#price-ZZA", "11.00")

      assert has_element?(view, ~s|#order-form input[name=ticker][value=ZZB]|)
      assert has_element?(view, ~s|#order-form input[name=quantity][value="7"]|)
      assert has_element?(view, ~s|#exit-form-long_sl input[name=ticker][value=ZZB]|)
      assert has_element?(view, ~s|#exit-form-long_sl input[name=limit][value="19.5"]|)
      assert has_element?(view, ~s|#exit-form-long_sl input[name=stop][value="18"]|)
    end
  end

  describe "limit orders (step G)" do
    # The "Long · stop-loss" exit panel is open by default.
    defp submit_limit(view, ticker, quantity, limit, stop) do
      select(view, ticker)

      view
      |> form("#exit-form-long_sl", %{
        quantity: quantity,
        limit: limit,
        stop: stop
      })
      |> render_submit()
    end

    test "a limit above the price rests in Open orders and can be cancelled", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZL", 105.0)

      submit_limit(view, "ZZL", "3", "100", "90")

      assert has_element?(
               view,
               "#order-message",
               "Placed limit buy 3 ZZL at $100.00, stop $90.00."
             )

      assert has_element?(view, "#open-orders", "limit buy 3 ZZL at $100.00, stop $90.00")
      assert has_element?(view, "#open-orders", "Waiting entry")

      view |> element("#open-orders button", "Cancel") |> render_click()
      assert has_element?(view, "#order-message", "Cancelled limit buy 3 ZZL")
      refute has_element?(view, "#open-orders")
    end

    test "a limit already above the price fills now and opens the stop-loss", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZL", 95.0)

      submit_limit(view, "ZZL", "2", "100", "90")
      assert has_element?(view, "#order-message", "Filled now: Bought 2 ZZL at $95.00 ($190.00)")
      assert has_element?(view, "#position-ZZL")
      assert has_element?(view, "#open-orders [id^=pending-]", "Stop-loss")
      assert has_element?(view, "#open-orders", "sell 2 at $90.00")
    end

    test "an invalid stop shows the error", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZL", 105.0)

      submit_limit(view, "ZZL", "1", "100", "120")
      assert has_element?(view, "#order-message", Trading.error_message(:invalid_stop))
    end

    test "OrderWatcher fills it from the price stream and the page updates", %{conn: conn} do
      watcher = start_supervised!({StockFetcher.OrderWatcher, source: :mock})
      view = mock_view_with_price(conn, "ZZL", 105.0)
      submit_limit(view, "ZZL", "4", "100", "")

      broadcast_price("ZZL", 99.0, "stocks:mock")
      # Wait for the watcher to handle the tick; its event reaches the view before our next call.
      :sys.get_state(watcher)

      assert has_element?(view, "#order-message", "Limit order filled: Bought 4 ZZL at $100.00")
      assert has_element?(view, "#position-ZZL")
      refute has_element?(view, "#open-orders")
    end
  end

  describe "shorts, brackets and moving exits (2026-11-07)" do
    test "Short and Cover from the short-selling form", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZS", 50.0)

      select(view, "ZZS")

      view
      |> form("#short-form", %{quantity: "4"})
      |> render_submit(%{side: "short"})

      assert has_element?(view, "#order-message", "Shorted 4 ZZS at $50.00 ($200.00)")
      assert has_element?(view, "#position-ZZS", "-4")
      assert has_element?(view, "#position-ZZS", "short")

      # A drop is a gain on a short: (45 - 50) * -4 = +$20.
      broadcast_price("ZZS", 45.0, "stocks:mock")
      assert has_element?(view, "#position-ZZS", "+$20.00")

      select(view, "ZZS")

      view
      |> form("#short-form", %{quantity: "4"})
      |> render_submit(%{side: "cover"})

      assert has_element?(view, "#order-message", "Covered 4 ZZS at $45.00 ($180.00)")
      refute has_element?(view, "#position-ZZS")
      assert has_element?(view, "#cash", "$100,020.00")
    end

    test "Buy on a short shows the short_open error", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZS", 50.0)

      select(view, "ZZS")

      view
      |> form("#short-form", %{quantity: "1"})
      |> render_submit(%{side: "short"})

      submit_order(view, "ZZS", "1", "buy")
      assert has_element?(view, "#order-message", Trading.error_message(:short_open))
    end

    test "a short bracket fills now and lists both exits with Move forms", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZB", 105.0)

      view |> element("#panel-short_sl button[phx-click=toggle_panel]") |> render_click()

      select(view, "ZZB")

      view
      |> form("#exit-form-short_sl", %{
        quantity: "2",
        limit: "100",
        stop: "110",
        take_profit: "80"
      })
      |> render_submit()

      assert has_element?(view, "#order-message", "Filled now: Shorted 2 ZZB at $105.00")
      assert has_element?(view, "#open-orders", "cover 2 at $110.00")
      assert has_element?(view, "#open-orders", "cover 2 at $80.00")
      assert has_element?(view, "#open-orders form[id^=amend-]")

      # Both exits sit in one bracket card: short, filled at $105, OCO, the price between them.
      [stop, tp] =
        Trading.list_pending_orders(session_portfolio_id(:mock)) |> Enum.sort_by(& &1.type, :desc)

      group = "#order-group-#{stop.parent_id}"
      assert stop.parent_id == tp.parent_id
      assert has_element?(view, group, "short")
      assert has_element?(view, group, "2 ZZB")
      assert has_element?(view, group, "filled at $105.00")
      assert has_element?(view, group, "OCO")
      assert has_element?(view, "#{group} #pending-#{stop.id}", "Stop-loss")
      assert has_element?(view, "#{group} #pending-#{tp.id}", "Take-profit")
      assert has_element?(view, group, "now $105.00")
    end

    test "Move raises the stop; a price past the market is refused", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZM", 95.0)
      submit_limit(view, "ZZM", "2", "100", "90")
      [stop] = Trading.list_pending_orders(session_portfolio_id(:mock))

      broadcast_price("ZZM", 110.0, "stocks:mock")
      assert has_element?(view, "#price-ZZM", "110.00")

      view |> form("#amend-#{stop.id}", %{trigger: "112"}) |> render_submit()
      assert has_element?(view, "#order-message", Trading.error_message(:would_fill_now))

      view |> form("#amend-#{stop.id}", %{trigger: "95"}) |> render_submit()
      assert has_element?(view, "#order-message", "Moved: stop-loss sell 2 ZZM at $95.00.")
      assert has_element?(view, "#open-orders", "sell 2 at $95.00")
    end

    test "OrderWatcher: take-profit fills and the stop is cancelled (OCO)", %{conn: conn} do
      watcher = start_supervised!({StockFetcher.OrderWatcher, source: :mock})
      view = mock_view_with_price(conn, "ZZO", 99.0)

      select(view, "ZZO")

      view
      |> form("#exit-form-long_sl", %{
        quantity: "1",
        limit: "100",
        stop: "90",
        take_profit: "110"
      })
      |> render_submit()

      broadcast_price("ZZO", 111.0, "stocks:mock")
      :sys.get_state(watcher)

      assert has_element?(
               view,
               "#order-message",
               "Take-profit filled: Sold 1 ZZO at $110.00 ($110.00). The other exit was cancelled (OCO)."
             )

      # History tags the automatic fills: the limit entry and the take-profit; a manual order
      # would have no tag.
      assert has_element?(view, "#orders li", "BUY 1 ZZO")
      assert has_element?(view, "#orders li", "limit entry")
      assert has_element?(view, "#orders li", "take-profit")

      refute has_element?(view, "#open-orders")
      refute has_element?(view, "#position-ZZO")
    end

    test "times are <time> elements the LocalTime hook rewrites in the browser", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZT", 10.0)

      assert has_element?(view, ~s|#price-ZZT time[phx-hook=LocalTime][datetime$="Z"]|)
      refute render(view) =~ "(UTC)"
      refute render(view) =~ "your local time"

      # The zone label: "UTC" from the server until the TimeZone hook writes PST, CST, ...
      assert has_element?(view, ~s|#tz-chart[phx-hook=TimeZone]|, "UTC")
      assert has_element?(view, ~s|#tz-watchlist[phx-hook=TimeZone]|, "UTC")
    end
  end

  describe "private portfolio, save file, sidebar and chart (2026-11-07)" do
    alias StockFetcher.Trading.SaveFile

    test "each tab gets its own portfolio; a trade in one doesn't show in the other", %{
      conn: conn
    } do
      a = mock_view_with_price(conn, "ZZP", 10.0)
      {:ok, b, _} = live(build_conn(), ~p"/prices?source=mock")

      submit_order(a, "ZZP", "1", "buy")
      assert has_element?(a, "#cash", "$99,990.00")
      assert has_element?(b, "#cash", "$100,000.00")
      refute has_element?(b, "#position-ZZP")
    end

    test "mount autosaves a signed save file the server can load again", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")
      assert_push_event(view, "save", %{source: :mock, file: file})
      assert {:ok, %{cash_cents: 10_000_000}} = SaveFile.import(file, :mock)
    end

    test "the browser's autosave in the connect params restores the portfolio" do
      {:ok, p} = Trading.create_session_portfolio(:mock, "5000")
      {:ok, _} = Trading.place_market_order(p.id, "buy", "AAPL", 3, 100.0, source: :mock)
      file = SaveFile.export(p.id, :mock)

      conn = put_connect_params(build_conn(), %{"save" => file})
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")

      assert has_element?(view, "#cash", "$4,700.00")
      assert has_element?(view, "#position-AAPL", "3")
      assert has_element?(view, "#orders", "BUY 3 AAPL")
      assert has_element?(view, "#account", "since start ($5,000.00)")
    end

    test "an edited autosave is refused and a fresh portfolio starts" do
      {:ok, p} = Trading.create_session_portfolio(:mock, "5000")
      file = String.replace(SaveFile.export(p.id, :mock), "500000", "900000")

      {:ok, view, _} =
        live(put_connect_params(build_conn(), %{"save" => file}), ~p"/prices?source=mock")

      assert has_element?(view, "#order-message", "autosave couldn't be loaded")
      assert has_element?(view, "#cash", "$100,000.00")
    end

    test "New portfolio with a chosen buying power, within $1,000 to $2,000,000", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")

      view |> form("#new-portfolio", %{starting_cash: "250000"}) |> render_submit()
      assert has_element?(view, "#order-message", "Started a new portfolio with $250,000.00.")
      assert has_element?(view, "#cash", "$250,000.00")

      view |> form("#new-portfolio", %{starting_cash: "500"}) |> render_submit()
      assert has_element?(view, "#order-message", Trading.error_message(:invalid_starting_cash))
      assert has_element?(view, "#cash", "$250,000.00")
    end

    test "New portfolio has no confirm popup; Undo brings the old one back", %{conn: conn} do
      view = mock_view_with_price(conn, "NVDA", 10.0)
      refute has_element?(view, "#new-portfolio [data-confirm]")

      submit_order(view, "NVDA", "5", "buy")
      view |> form("#new-portfolio", %{starting_cash: "5000"}) |> render_submit()
      assert has_element?(view, "#cash", "$5,000.00")
      assert has_element?(view, "#order-message", "Started a new portfolio with $5,000.00.")

      view |> element("#undo-button") |> render_click()
      assert has_element?(view, "#order-message", "Your previous portfolio is back.")
      assert has_element?(view, "#position-NVDA", "5")
      refute has_element?(view, "#undo-button")
    end

    test "no Undo for an untouched portfolio; New twice keeps the Undo for the traded one", %{
      conn: conn
    } do
      view = mock_view_with_price(conn, "NVDA", 10.0)
      view |> form("#new-portfolio", %{starting_cash: "5000"}) |> render_submit()
      refute has_element?(view, "#undo-button")

      submit_order(view, "NVDA", "1", "buy")
      view |> form("#new-portfolio", %{starting_cash: "7000"}) |> render_submit()
      view |> form("#new-portfolio", %{starting_cash: "9000"}) |> render_submit()
      view |> element("#undo-button") |> render_click()
      # The first $5,000 portfolio, with its 1 share (a real ticker: save files only take the 50).
      assert has_element?(view, "#position-NVDA", "1")
      assert has_element?(view, "#account", "since start ($5,000.00)")
    end

    test "the next trade ends the Undo", %{conn: conn} do
      view = mock_view_with_price(conn, "NVDA", 10.0)
      submit_order(view, "NVDA", "1", "buy")
      view |> form("#new-portfolio", %{starting_cash: "5000"}) |> render_submit()
      assert has_element?(view, "#undo-button")

      submit_order(view, "NVDA", "1", "buy")
      refute has_element?(view, "#undo-button")
    end

    test "Import offers Undo too", %{conn: conn} do
      view = mock_view_with_price(conn, "NVDA", 10.0)
      submit_order(view, "NVDA", "2", "buy")
      {:ok, other} = Trading.create_session_portfolio(:mock, "3000")

      render_hook(view, "import_save", %{"file" => SaveFile.export(other.id, :mock)})
      assert has_element?(view, "#cash", "$3,000.00")

      view |> element("#undo-button") |> render_click()
      assert has_element?(view, "#position-NVDA", "2")
    end

    test "Import loads a save file; a bad one shows why", %{conn: conn} do
      {:ok, p} = Trading.create_session_portfolio(:mock, "20000")
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")

      render_hook(view, "import_save", %{"file" => SaveFile.export(p.id, :mock)})
      assert has_element?(view, "#order-message", "Save file loaded.")
      assert has_element?(view, "#cash", "$20,000.00")

      render_hook(view, "import_save", %{"file" => "{}"})
      assert has_element?(view, "#order-message", SaveFile.error_message(:invalid_file))

      render_hook(view, "import_save", %{"too_large" => true})
      assert has_element?(view, "#order-message", SaveFile.error_message(:too_large))
    end

    test "clicking a watchlist row charts it and selects it in the forms", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")
      assert_push_event(view, "chart:data", %{ticker: "AAPL", interval: 60})

      view |> element("#price-QBTS") |> render_click()

      assert_push_event(view, "chart:data", %{ticker: "QBTS", candles: candles})
      assert length(candles) >= 120
      # No dropdowns: a chip shows the selection, the forms submit it as a hidden "ticker".
      refute has_element?(view, "select[name=ticker]")
      assert has_element?(view, "#trade-ticker", "D-Wave Quantum")
      assert has_element?(view, "#trade-ticker-QBTS.chip-flash")
      assert has_element?(view, ~s|#order-form input[type=hidden][name=ticker][value=QBTS]|)
      assert has_element?(view, ~s|#short-form input[type=hidden][name=ticker][value=QBTS]|)

      assert has_element?(
               view,
               ~s|#exit-form-long_sl input[type=hidden][name=ticker][value=QBTS]|
             )

      assert has_element?(view, "#order-form button", "Buy QBTS")
      assert has_element?(view, "#short-form button", "Cover QBTS")
      assert has_element?(view, "#exit-form-long_sl button", "Place long entry · QBTS")
    end

    test "trade buttons stay disabled until the selected ticker has a price", %{conn: conn} do
      # On the live page in tests, QBTS has no price: no DB row, no poller, and no other test
      # sends it a tick (the shared live candle cache would otherwise give it a fallback price).
      {:ok, view, _} = live(conn, ~p"/prices")
      select(view, "QBTS")
      assert has_element?(view, "#order-form button[disabled]", "Buy QBTS")
      assert has_element?(view, "#short-form button[disabled]", "Short QBTS")

      # The Alpaca topic prices it.
      broadcast_price("QBTS", 10.5, "stocks:extra")
      assert has_element?(view, "#price-QBTS", "10.50")
      refute has_element?(view, "#order-form button[disabled]")
      assert has_element?(view, "#trade-ticker", "$10.50")
    end

    test "the watchlist lists all 50 tickers and takes the extra mock topic", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")
      for t <- StockFetcher.Tickers.all(), do: assert(has_element?(view, "#price-#{t}"))

      broadcast_price("ZZEXTRA", 7.0, "stocks:mock:extra")
      assert has_element?(view, "#price-ZZEXTRA", "7.00")
    end

    test "exit panels: opening one closes the others", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")
      assert has_element?(view, "#exit-form-long_sl")

      view |> element("#panel-short_tp button[phx-click=toggle_panel]") |> render_click()
      assert has_element?(view, "#exit-form-short_tp")
      refute has_element?(view, "#exit-form-long_sl")
      assert has_element?(view, "#panel-short_tp", "Profit from a fall")
    end

    test "Example prices fills a valid setup and the risk preview", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZX", 100.0)
      select(view, "ZZX")
      view |> form("#exit-form-long_sl", %{quantity: "10"}) |> render_change()

      view |> element("#exit-form-long_sl button", "Example prices") |> render_click()

      assert has_element?(view, ~s|#exit-form-long_sl input[name=limit][value="99.50"]|)
      assert has_element?(view, ~s|#exit-form-long_sl input[name=stop][value="97.00"]|)
      assert has_element?(view, ~s|#exit-form-long_sl input[name=take_profit][value="105.00"]|)
      assert has_element?(view, "#exit-form-long_sl", "risk $25.00")
      assert has_element?(view, "#exit-form-long_sl", "R:R 1:2.2")
    end

    test "the watchlist filter: a Flash hook box LiveView leaves alone, rows carry ticker and name",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")

      # The hook filters in the browser; the server only renders what it needs.
      assert has_element?(
               view,
               ~s|#watchlist-filter[phx-hook=Flash][phx-update=ignore] input[data-flash-input]|
             )

      assert has_element?(view, ~s|#watchlist-filter style[data-flash-style]|)

      assert has_element?(
               view,
               ~s|#price-JNJ[data-ticker=JNJ][data-name="Johnson & Johnson"] .flash-label|
             )

      assert has_element?(view, "#watchlist-empty.hidden")
    end

    test "jump keys: fixed letters on number inputs, free letters on Move boxes, none on buttons",
         %{conn: conn} do
      view = mock_view_with_price(conn, "ZZJ", 100.0)

      for {selector, key} <- [
            {"#order-form input[name=quantity]", "b"},
            {"#short-form input[name=quantity]", "s"},
            {"#exit-form-long_sl input[name=quantity]", "q"},
            {"#exit-form-long_sl input[name=limit]", "e"},
            {"#exit-form-long_sl input[name=stop]", "x"},
            {"#exit-form-long_sl input[name=take_profit]", "t"},
            {"#new-portfolio input[name=starting_cash]", "n"}
          ] do
        assert has_element?(view, ~s|#{selector}[data-jump="#{key}"]|)
      end

      # The only buttons with a key are the closed exit-panel headers (a d f g); the open one
      # (Long · stop-loss) has none.
      assert has_element?(view, ~s|#panel-long_tp button[data-jump="a"]|)
      assert has_element?(view, ~s|#panel-short_tp button[data-jump="f"]|)
      assert has_element?(view, ~s|#panel-short_sl button[data-jump="g"]|)
      refute has_element?(view, "#panel-long_sl button[data-jump]")
      refute has_element?(view, "#panel-long_sl > .jump-label")
      refute has_element?(view, "#order-form button[data-jump]")
      refute has_element?(view, "#exit-form-long_sl button[data-jump]")
      # "l" and "i" are never used: they look alike in many fonts.
      refute has_element?(view, ~s|[data-jump="l"]|)
      refute has_element?(view, ~s|[data-jump="i"]|)

      # A filled bracket opens two exits: their Move boxes get h and j (a d f g are the panels).
      select(view, "ZZJ")

      view
      |> form("#exit-form-long_sl", %{quantity: "1", limit: "105", stop: "90", take_profit: "120"})
      |> render_submit()

      assert has_element?(view, ~s|#open-orders input[name=trigger][data-jump="h"]|)
      assert has_element?(view, ~s|#open-orders input[name=trigger][data-jump="j"]|)
      assert has_element?(view, "#open-orders .jump-label", "h")

      # Opening another panel moves the label: Long · stop-loss gets "d" back.
      view |> element("#panel-short_tp button[phx-click=toggle_panel]") |> render_click()
      refute has_element?(view, "#panel-short_tp button[data-jump]")
      assert has_element?(view, ~s|#panel-long_sl button[data-jump="d"]|)
    end

    test "positions, open orders and history are three panels", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")
      assert has_element?(view, "#positions-panel", "Positions")
      assert has_element?(view, "#positions-panel #cash", "$100,000.00")
      assert has_element?(view, "#open-orders-panel", "No open orders.")
      assert has_element?(view, "#history-panel", "No orders yet.")
    end

    test "clicking an open order charts it with dotted lines in its chip colours", %{conn: conn} do
      view = mock_view_with_price(conn, "ZZF", 100.0)
      select(view, "ZZF")

      view
      |> form("#exit-form-long_sl", %{quantity: "1", limit: "101", stop: "95", take_profit: "110"})
      |> render_submit()

      [stop, tp] =
        Trading.list_pending_orders(session_portfolio_id(:mock)) |> Enum.sort_by(& &1.type, :desc)

      select(view, "AAPL")
      # Each select/2 pushed a "clear"; drain both so later asserts only see new events.
      assert_push_event(view, "chart:lines", %{lines: []})
      assert_push_event(view, "chart:lines", %{lines: []})

      view |> element("#order-group-#{stop.parent_id}") |> render_click()

      assert_push_event(view, "chart:data", %{ticker: "ZZF"})

      # Highest price first: take-profit (blue) above stop-loss (orange).
      assert_push_event(view, "chart:lines", %{
        lines: [
          %{price: 110.0, color: "#3b82f6", title: "TP"},
          %{price: 95.0, color: "#f97316", title: "SL"}
        ]
      })

      assert has_element?(view, "#order-group-#{stop.parent_id}.ring-2")
      assert has_element?(view, "#trade-ticker", "ZZF")
      # Chips use the same colours: orange stop-loss, blue take-profit.
      assert has_element?(view, "#pending-#{stop.id} .bg-orange-100", "Stop-loss")
      assert has_element?(view, "#pending-#{tp.id} .bg-blue-100", "Take-profit")

      # Move shifts its line.
      view |> form("#amend-#{stop.id}", %{trigger: "97"}) |> render_submit()

      assert_push_event(view, "chart:lines", %{
        lines: [%{title: "TP", price: 110.0}, %{title: "SL", price: 97.0}]
      })

      # Cancelling one exit keeps the bracket; cancelling the last clears the lines.
      view |> element("#pending-#{tp.id} button", "Cancel") |> render_click()
      assert_push_event(view, "chart:lines", %{lines: [%{title: "SL"}]})
      view |> element("#pending-#{stop.id} button", "Cancel") |> render_click()
      assert_push_event(view, "chart:lines", %{lines: []})
      refute has_element?(view, ".ring-2")
    end

    test "a waiting entry shows its entry, stop and take-profit; another ticker clears", %{
      conn: conn
    } do
      view = mock_view_with_price(conn, "ZZW", 100.0)
      select(view, "ZZW")
      assert_push_event(view, "chart:lines", %{lines: []})

      view
      |> form("#exit-form-long_sl", %{quantity: "1", limit: "90", stop: "85", take_profit: "99"})
      |> render_submit()

      [entry] = Trading.list_pending_orders(session_portfolio_id(:mock))
      view |> element("#order-group-#{entry.id}") |> render_click()
      assert_push_event(view, "chart:lines", %{lines: [_ | _] = lines})
      assert Enum.map(lines, & &1.title) == ["Entry", "SL", "TP"]

      select(view, "AAPL")
      assert_push_event(view, "chart:lines", %{lines: []})
    end

    test "the help panel is on the page, hidden until the button shows it", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/prices?source=mock")
      assert has_element?(view, "#help-panel.hidden", "How paper trading works")
      assert has_element?(view, "#help-button")
    end
  end

  # The only session portfolio for a source in this test's sandbox (one view open).
  defp session_portfolio_id(source) do
    import Ecto.Query

    StockFetcher.Repo.one!(
      from(p in StockFetcher.Trading.Portfolio,
        where: like(p.name, ^"session:#{source}:%"),
        select: p.id
      )
    )
  end

  # Overrides the test clock from config/test.exs for one test (this module is async: false).
  defp pin_clock(now) do
    previous = Application.get_env(:stock_fetcher, :trading_fixed_now)
    Application.put_env(:stock_fetcher, :trading_fixed_now, now)
    on_exit(fn -> Application.put_env(:stock_fetcher, :trading_fixed_now, previous) end)
  end

  defp mock_view_with_price(conn, ticker, price) do
    {:ok, view, _html} = live(conn, ~p"/prices?source=mock")
    broadcast_price(ticker, price, "stocks:mock")
    # Waits until the broadcast is handled, so the ticker is in the dropdown.
    assert has_element?(view, "#price-#{ticker}")
    view
  end

  # Picks a ticker the way a user does: clicking its watchlist row. Every form then trades it.
  defp select(view, ticker) do
    view |> element("#price-#{ticker}") |> render_click()
  end

  # "side" is the clicked button (the form's submitter), passed as an extra value.
  defp submit_order(view, ticker, quantity, side) do
    select(view, ticker)

    view
    |> form("#order-form", %{quantity: quantity})
    |> render_submit(%{side: side})
  end

  defp broadcast_price(ticker, price, topic \\ "stocks:live") do
    Phoenix.PubSub.broadcast(
      StockFetcher.PubSub,
      topic,
      {"new_price", %{id: 1, ticker: ticker, price: price, timestamp: DateTime.utc_now()}}
    )
  end
end
