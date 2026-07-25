defmodule StockFetcherWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :stock_fetcher

  # Parse JSON request bodies into the `conn.params` map using Jason
  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  # Dispatch to router
  plug(StockFetcherWeb.Router)
end
