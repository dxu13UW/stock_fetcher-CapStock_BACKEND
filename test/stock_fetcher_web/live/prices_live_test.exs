defmodule StockFetcherWeb.PricesLiveTest do
  use StockFetcherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # "stocks:live" is one global topic, so other async tests' broadcasts can reach these
  # LiveViews too. Each test uses a ZZ* ticker no other test uses and only asserts on it.

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

  defp broadcast_price(ticker, price) do
    Phoenix.PubSub.broadcast(
      StockFetcher.PubSub,
      "stocks:live",
      {"new_price", %{id: 1, ticker: ticker, price: price, timestamp: DateTime.utc_now()}}
    )
  end
end
