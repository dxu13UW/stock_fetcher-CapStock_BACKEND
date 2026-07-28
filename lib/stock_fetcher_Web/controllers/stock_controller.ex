defmodule StockFetcherWeb.StockController do
  use Phoenix.Controller, formats: [:json]
  alias StockFetcher.{Repo, StockPrice}
  import Ecto.Query

  def index(conn, _params) do
    # Fetch the 50 most recent records from SQLite
    prices =
      from(p in StockPrice, order_by: [desc: p.inserted_at], limit: 50)
      |> Repo.all()

    json(conn, %{data: format_prices(prices)})
  end

  # --- Helper Functions ---

  defp format_prices(prices) do
    Enum.map(prices, fn p ->
      %{
        id: p.id,
        ticker: p.ticker,
        price: p.price,
        timestamp: p.inserted_at
      }
    end)
  end
end
