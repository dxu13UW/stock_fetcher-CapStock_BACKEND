defmodule StockFetcherWeb.StockChannel do
  use Phoenix.Channel
  alias StockFetcher.{Repo, StockPrice}
  import Ecto.Query
  require Logger

  # Client joins the topic "stocks:live"
  @impl true
  def join("stocks:live", _params, socket) do
    # Stream stock price updates
    Phoenix.PubSub.subscribe(StockFetcher.PubSub, "stocks:broadcasts")

    # Returning `{:ok, payload, socket}` sends the payload immediately as the join response
    {:ok, %{initial_data: fetch_recent_prices(50)}, socket}
  end

  @impl true
  def handle_in("request_historical", %{"limit" => limit}, socket) do
    # Clamp limit to prevent massive DB memory dumps
    bounded_limit = min(limit, 500)
    history = fetch_recent_prices(bounded_limit)

    {:reply, {:ok, %{data: history}}, socket}
  end

  @impl true
  def handle_info({:new_price, stock_data}, socket) do
    push(socket, "new_price", stock_data)
    {:noreply, socket}
  end

  @impl true
  def terminate(reason, socket) do
    Logger.info("Client disconnected from '#{socket.topic}'. Reason: #{inspect(reason)}")
    :ok
  end

  # --- Helper Query ---

  defp fetch_recent_prices(limit) do
    from(p in StockPrice, order_by: [desc: p.inserted_at], limit: ^limit)
    |> Repo.all()
    |> Enum.map(fn p ->
      %{
        id: p.id,
        ticker: p.ticker,
        price: p.price,
        timestamp: p.inserted_at
      }
    end)
  end
end
