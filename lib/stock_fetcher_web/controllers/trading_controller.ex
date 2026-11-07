defmodule StockFetcherWeb.TradingController do
  @moduledoc """
  JSON API for the React trading panel (step F). Same `Trading` module as the LiveView panel,
  so both UIs fill orders by the same rules and show the same messages.

    GET  /api/portfolio  -> 200 %{portfolio: ...}
    POST /api/orders     %{"ticker", "side", "quantity"}
                         -> 201 %{order, portfolio, message} | 422 %{error, message}

  Amounts are integer cents; the client formats them. There is one shared demo portfolio and no
  login, the same as the LiveView page.
  """
  use Phoenix.Controller, formats: [:json]

  alias StockFetcher.Trading
  alias StockFetcher.Trading.{Order, Portfolio, Position}

  def portfolio(conn, _params) do
    portfolio = Trading.demo_portfolio()
    json(conn, %{portfolio: portfolio_json(portfolio, Trading.list_orders(portfolio.id))})
  end

  def create_order(conn, params) do
    ticker = params["ticker"]

    # The server prices the order. A "price" in the body is ignored on purpose: a client could
    # send any number. See StockFetcher.latest_price/1 for why this matches the client's screen.
    price = StockFetcher.latest_price(ticker)
    portfolio = Trading.demo_portfolio()

    result =
      Trading.place_market_order(portfolio.id, params["side"], ticker, params["quantity"], price)

    case result do
      {:ok, %{order: order, portfolio: portfolio}} ->
        conn
        |> put_status(:created)
        |> json(%{
          order: order_json(order),
          portfolio: portfolio_json(portfolio, Trading.list_orders(portfolio.id)),
          message: Trading.confirmation(order)
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_content)
        |> json(%{
          error: reason,
          message: Trading.error_message(reason)
        })
    end
  end

  # --- JSON shapes (explicit fields, so nothing internal like __meta__ leaks out) ---

  defp portfolio_json(%Portfolio{} = portfolio, orders) do
    %{
      cash_cents: portfolio.cash_cents,
      positions: Enum.map(portfolio.positions, &position_json/1),
      orders: Enum.map(orders, &order_json/1)
    }
  end

  defp position_json(%Position{} = position) do
    %{
      ticker: position.ticker,
      quantity: position.quantity,
      avg_cost_cents: position.avg_cost_cents
    }
  end

  defp order_json(%Order{} = order) do
    %{
      id: order.id,
      ticker: order.ticker,
      side: order.side,
      quantity: order.quantity,
      price_cents: order.price_cents,
      total_cents: order.total_cents,
      inserted_at: order.inserted_at
    }
  end
end
