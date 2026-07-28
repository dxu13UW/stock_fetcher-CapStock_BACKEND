defmodule StockFetcherWeb.Router do
  @moduledoc """
  The HTTP Request Dispatcher and Pipeline Manager for the application.
  """
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])

    plug(CORSPlug, origin: ["http://localhost:5173", "http://localhost:3000"])
  end

  scope "/api", StockFetcherWeb do
    pipe_through(:api)

    get("/stocks", StockController, :index)
  end
end
