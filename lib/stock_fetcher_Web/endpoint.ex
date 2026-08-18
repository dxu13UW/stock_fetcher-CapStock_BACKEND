defmodule StockFetcherWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :stock_fetcher

  socket "/socket", StockFetcherWeb.UserSocket,
    websocket: [
      check_origin: [
        "https://tinle-ri.github.io",
        "http://localhost:5173",
        "http://localhost:4000"
      ]
    ],
    longpoll: false

  plug Corsica,
    origins: [
      "https://tinle-ri.github.io",
      "http://localhost:5173",
      "http://localhost:4000"
    ],
    allow_headers: ["content-type", "accept"],
    allow_methods: ["GET", "POST", "OPTIONS"]

  # Parse JSON request bodies into the `conn.params` map using Jason
  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  # Dispatch to router
  plug(StockFetcherWeb.Router)
end
