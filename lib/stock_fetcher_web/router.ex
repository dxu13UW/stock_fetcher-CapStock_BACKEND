defmodule StockFetcherWeb.Router do
  @moduledoc """
  The HTTP Request Dispatcher and Pipeline Manager for the application.
  """
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  # Browser pages (LiveView). The React SPA never goes through this pipeline.
  pipeline :browser do
    plug :accepts, ["html"]
    # Read the session cookie; LiveView passes it to mount/3 and checks CSRF with it.
    plug :fetch_session
    plug :fetch_live_flash
    # Wrap every page in components/layouts/root.html.heex.
    plug :put_root_layout, html: {StockFetcherWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

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

  scope "/", StockFetcherWeb do
    pipe_through :browser

    live "/prices", PricesLive
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
