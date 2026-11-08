defmodule StockFetcherWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :stock_fetcher

  # Session cookie for browser pages (LiveView needs it for CSRF and mount/3's session).
  # The cookie is signed with secret_key_base; the salt is not a secret.
  @session_options [
    store: :cookie,
    key: "_stock_fetcher_key",
    signing_salt: "257aqPZF",
    same_site: "Lax"
  ]

  # React SPA channel socket (unchanged).
  socket "/socket", StockFetcherWeb.UserSocket,
    websocket: [
      check_origin: [
        "https://tinle-ri.github.io",
        "http://localhost:5173",
        "http://localhost:4000"
      ]
    ],
    longpoll: false

  # LiveView socket. Each connected LiveView page runs as a process behind this socket.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serves the built CSS/JS from priv/static/assets.
  plug Plug.Static,
    at: "/",
    from: :stock_fetcher,
    gzip: false,
    only: StockFetcherWeb.static_paths()

  # Dev only: recompile changed code on request and refresh the browser on file changes.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

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

  plug Plug.Session, @session_options

  # Dispatch to router
  plug(StockFetcherWeb.Router)
end
