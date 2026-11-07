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
    # The mock source starts with no prices, so each test broadcasts its own ZZ* ticker.
    # Every test gets a fresh DB (SQL sandbox), so the demo portfolio starts at $100,000.

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

  # "side" is the clicked button (the form's submitter), passed as an extra value.
  defp submit_order(view, ticker, quantity, side) do
    view
    |> form("#order-form", %{ticker: ticker, quantity: quantity})
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
