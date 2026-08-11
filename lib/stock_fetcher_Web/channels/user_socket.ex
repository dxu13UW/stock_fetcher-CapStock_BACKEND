# lib/stock_fetcher_web/channels/user_socket.ex
defmodule StockFetcherWeb.UserSocket do
  use Phoenix.Socket

  # Matches "stocks:live", "stocks:mock", or any "stocks:<subtopic>"
  channel "stocks:*", StockFetcherWeb.StockChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
