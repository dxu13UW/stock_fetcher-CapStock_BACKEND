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
      ],
      # React only sends small channel messages; Bandit's default cap is 8 MB.
      max_frame_size: 100_000
    ],
    longpoll: false

  # LiveView socket. Each connected LiveView page runs as a process behind this socket.
  #
  # max_frame_size: the biggest real message is the join carrying the browser's autosave (a save
  # file is at most 1 MB, a bit more once escaped inside JSON), so 2 MB instead of Bandit's 8 MB
  # default. peer_data/x_headers: the client IP for the per-IP connection limit in PricesLive.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [:peer_data, :x_headers, session: @session_options],
      max_frame_size: 2_000_000
    ],
    longpoll: [connect_info: [:peer_data, :x_headers, session: @session_options]]

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
