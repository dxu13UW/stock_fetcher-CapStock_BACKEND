# CLAUDE.md — Capstock (stock_fetcher), Artifact 4

## Who you're working with
Daniel is an Elixir learner building this solo for TCSS 490 Artifact 4 ("For Someone Else"),
approved to work alone. The goal is learning, not just shipping:
- Explain *why* behind OTP/LiveView decisions (process boundaries, supervision, failure modes).
- Before writing non-trivial code, ask Daniel to attempt the design or the last step first.
  Hand back the final step rather than finishing everything; review his attempt after.
- When comparing approaches, state trade-offs plainly, including where LiveView loses to React.

## Project snapshot
- Stack: Elixir ~> 1.18, Phoenix 1.7 (Bandit), Ecto + SQLite (ecto_sqlite3), Req, Hammer,
  :telemetry, Phoenix.PubSub. Deployed on Fly.io (single machine).
- Market data: Finnhub (existing Worker) + Alpaca market data API (free tier, added for
  Artifact 4). See "Alpaca" below and `PLAN.md` §5 "Data sources".
- Existing React SPA frontend (separate repo) consumes the JSON API and `StockChannel`.
  **It must keep working.** LiveView is added alongside it, not as a replacement, during this artifact.
- Supervision tree (`lib/stock_fetcher/application.ex`, :one_for_one):
  Repo → Worker (polls Finnhub every 15s, 5 tickers) → Pruner → PubSub → Mock.Streamer → Endpoint.
- Live data flow: Worker → `fetch_stock_data/1` → `save_price/2` → telemetry event →
  `TelemetryHandler` → `PubSub.broadcast("stocks:live", {"new_price", payload})` → subscribers.
  New LiveViews should subscribe to the same topic rather than adding new polling.
- Planned (step B2): an Alpaca poller GenServer for tickers Finnhub doesn't cover (e.g. QBTS),
  broadcasting to "stocks:live" in the **same payload format** as the Worker, so consumers
  can't tell sources apart.

## Alpaca
- Free paper-account key, used for **market data only** (`data.alpaca.markets`). Never call
  Alpaca's trading/order endpoints (`paper-api.alpaca.markets/v2/orders` etc.): fills,
  positions, and cash belong to Capstock's own trading module.
- Keys: env vars `ALPACA_KEY_ID`, `ALPACA_SECRET`. Locally in `.env` (git-ignored; values are
  quoted, so strip quotes when loading); `fly secrets` in production. Never print, log, or
  commit them.
- Free tier (tested 2026-10-30): 200 requests/min. One latest-trades request covers many
  symbols. IEX feed (`feed=iex`) is real-time but one exchange (~7% of volume). SIP feed
  (`feed=sip`): recent trades return 403; historical bars (incl. `timeframe=4Hour`, back to at
  least 2024) work. Request SIP bars with `end` ≥ 15 min in the past.
- Live prices: IEX via polling (not the WebSocket stream). 4-hour bars (step I): SIP, cached in
  the DB, never fetched per page view.
- One live source per ticker. The Finnhub Worker keeps AAPL, AMZN, GOOGL, MSFT, TSLA unchanged.

## Constraints
- Finnhub free tier: 60 calls/min. Current usage is ~20/min. Alpaca free tier: 200 calls/min;
  the planned poller uses ~4/min. Do not add per-user or per-LiveView API calls to either;
  derive everything from the existing broadcast stream or the DB.
- SQLite = single writer, single node. Don't design anything that assumes multiple nodes yet.
- Money and quantities: integer cents or `Decimal`, never floats.
- Trading is **simulated (paper trading)** only. No real orders, brokers, or payment providers.
  Alpaca is a data source, not a broker, in this project.

## Known issues (don't make worse; fix only when it's the planned task)
- `Task.async_stream` in Worker: default `on_timeout: :exit` crashes the Worker on slow fetches;
  `handle_fetch_result({:error, _})` is dead code (stream yields `{:ok, _}` / `{:exit, _}`).
- `TelemetryHandler` raising would detach the handler and silently stop live updates.
- PubSub child starts after Worker/Pruner (works only because the first poll is delayed).
- `StockChannel` intercept/handle_out for "new_price" likely never fires.

## Artifact 4 scope
User story (to be refined by interview): a day trader wants a day-trading simulation using
real-time prices, plus simulated dividends. Further features to be discovered by asking.
Dev goals: learn LiveView fundamentals; compare server-rendered LiveView with the React SPA.

Feature split:
- **Benchmark feature, built in BOTH UIs:** buy/sell paper-trading panel. One shared Elixir
  trading module; LiveView calls it from `handle_event`, React reaches it via new API endpoints or
  channel messages (in the separate React repo).
- **LiveView only:** everything else (dividends, features from the user interview).

Benchmark panel spec (both UIs must match exactly, or the metrics compare features, not philosophies):
- Inputs: ticker, quantity, buy/sell. Market orders filled at the latest broadcast price.
- Feedback: order confirmation, updated position and cash.
- Errors: insufficient cash, selling more than held, unknown ticker.

First tasks, in order:
1. Check whether LiveView deps/layouts exist (`phoenix_live_view`, `phoenix_html`, esbuild/tailwind).
   The app may have been generated as JSON-only; add what's missing without breaking `/api` routes.
2. A read-only `PricesLive` page subscribed to "stocks:live". Then the Alpaca poller (B2).
3. Shared paper-trading module (orders, positions, cash) as plain functions with tests.
   Both UIs depend on it, so it comes before either panel. Then decide the process design.
4. LiveView trading panel, then the React trading panel (API/channel additions + React UI).
5. Dividends: verify what Finnhub's free tier provides before designing; fall back to seeded data.

## Metrics (dev story #2)
Both UIs run against the same backend and price stream so the frontend is the only variable.
Before measuring, record a prediction in LOG.md; afterwards record the result and the gap.
- First load: JS bundle size, bytes transferred, time until prices appear (DevTools, Lighthouse).
- Per-update cost: WebSocket bytes per price tick (DevTools > Network > WS > Messages).
- Interaction latency: click Buy → confirmation visible, normal network and throttled.
- Server cost per user: `Process.info(pid, :memory)` per LiveView vs channel process.
- Client cost: browser CPU/memory (DevTools Performance).
- Developer cost: lines changed and hours to build the trading panel in each UI.

## Branching and deploys
- Work on the `liveview` branch of this repo; merge to `main` when ready. No separate repo.
- Optional staging: a second Fly app (e.g. `fly deploy --app capstock-live`) for the branch.
  Staging must not poll Finnhub or Alpaca (disable Worker and the Alpaca poller via env var; use
  `Mock.Streamer`) and has its own SQLite.
- Production stays one app serving both `/api` + channels (React) and LiveView routes.

Open questions (resolve with the user, record answers in LOG.md):
accounts vs. one demo portfolio; order types (market only? limit?); starting cash; how dividends
should appear; what "smooth" means to them on the current React UI.

## Repo conventions
- `PLAN.md`: the agreed plan. Read it before starting work; propose edits rather than drifting.
- `LOG.md`: dated entries of what was planned, what changed, and why. Append after each session.
  Include user feedback and LiveView vs React observations (these feed the reflection).
- Keep GenServers testable via injected deps (`now_fn`, `test_pid`, `schedule_timer`) as existing code does.
- Before finishing a change: `mix format`, `mix compile --warnings-as-errors`, `mix test`.
- Dev environment: WSL (`~/ELIXIR/stock_fetcher`); a Windows copy exists — edit the WSL one.

## Deliverables (due Sun Nov 8, 11:59 PM; check-in Sun Nov 1)
Working features shown to the user, PLAN.md + LOG.md in the repo, portfolio card with link and reflection.
