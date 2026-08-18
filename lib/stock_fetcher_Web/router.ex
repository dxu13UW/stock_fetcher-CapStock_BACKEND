defmodule StockFetcherWeb.Router do
  @moduledoc """
  The HTTP Request Dispatcher and Pipeline Manager for the application.
  """
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]

    plug CORSPlug,
      origin: [
        "http://localhost:5173",
        "http://localhost:3000",
        "https://tinle-ri.github.io"
      ]
  end

  pipeline :hydration_protected do
    plug StockFetcherWeb.Plugs.HydrationLimiter
  end

  scope "/api", StockFetcherWeb do
    pipe_through :api

    # Unprotected / lightweight endpoints
    get "/health", HealthController, :show

    # Protected endpoints (Path must be provided to scope)
    scope "/" do
      pipe_through :hydration_protected
      get "/stocks", StockController, :index
    end
  end
end
