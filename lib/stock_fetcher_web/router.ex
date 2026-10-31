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
    plug StockFetcherWeb.Plugs.HydrationLimiter,
      limit: 20,
      scale_ms: 60_000,
      key_prefix: "hydrate",
      error: "Hydration rate limit exceeded.",
      message: "Please stop refreshing the page. Data is streamed to client via active Websocket."
  end

  pipeline :interactive_protected do
    plug StockFetcherWeb.Plugs.HydrationLimiter,
      limit: 120,
      scale_ms: 60_000,
      key_prefix: "zoom",
      error: "Zoom rate limit exceeded.",
      message: "Too many interactive zoom requests. Please slow down."
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

    scope "/" do
      pipe_through :interactive_protected
      get "/stocks/:ticker/intraday", StockController, :intraday
    end
  end
end
