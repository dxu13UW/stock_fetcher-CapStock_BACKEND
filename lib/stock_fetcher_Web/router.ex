defmodule StockFetcherWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
    # Allow local React dev server origins (e.g. Vite default 5173 or CRA 3000)
    plug(CORSPlug,
      origin: ["http://localhost:5173", "http://localhost:3000", "http://localhost:8080"]
    )
  end

  scope "/api", StockFetcherWeb do
    pipe_through(:api)

    get("/stocks", StockController, :index)
  end
end
