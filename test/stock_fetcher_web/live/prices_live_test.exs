defmodule StockFetcherWeb.PricesLiveTest do
  use StockFetcherWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the prices page", %{conn: conn} do
    # live/2 does both mounts: the HTTP render, then the connected (WebSocket) one.
    {:ok, _view, html} = live(conn, ~p"/prices")

    assert html =~ "Live Prices"
  end

  # TODO(5) After TODO(1)-(4): prove the page updates from a broadcast.
  #
  #   {:ok, view, _html} = live(conn, ~p"/prices")
  #   Phoenix.PubSub.broadcast(StockFetcher.PubSub, "stocks:live",
  #     {"new_price", %{id: 1, ticker: "TEST", price: 1.23, timestamp: NaiveDateTime.utc_now()}})
  #   assert render(view) =~ "TEST"
  #
  #   "stocks:live" is one global topic, so other async tests could receive this message
  #   too. Use a ticker no other test uses, or make this module `async: false`.
end
