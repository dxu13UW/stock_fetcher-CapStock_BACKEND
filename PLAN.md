# PLAN.md — Capstock LiveView: Day-Trading Simulator (Artifact 4)

This is the agreed plan for TCSS 490 Artifact 4 ("For Someone Else"). It is the single source
of truth for me and for my agent (`CLAUDE.md` points here). Changes to this plan are proposed,
agreed, and then recorded in `LOG.md` with the reason.

## 1. Team and ownership

- **Team:** Daniel Xu (solo). I have received permission to complete Artifact 4 on my own
  instead of in a pair or trio.
- **Ownership:** I own the full project: backend (Elixir/Phoenix), the LiveView UI, the React
  SPA changes (separate repo), deployment, the user interview and handover, `PLAN.md`, `LOG.md`,
  and the portfolio card.
- **Collaborators:** my AI agent (Claude Code). Its instructions live in `CLAUDE.md`, which
  references this plan.
- Remote branches `mtpbranch` and `tinbranch` predate Artifact 4 and are not part of this work.

## 2. Who it is for

- **User:** "John Daytrader" (pseudonym), a day trader who asked to remain anonymous. Their
  real name and contact details are kept out of the repo.
- **Starting user story:** "As a day trader, I want to practice day trading against real-time
  prices with simulated money, including simulated dividends, so I can test strategies without
  risking real capital."
- The story is refined by interview. Features the user asks for take priority over my own
  dev goals (section 3).
- **Handover:** demo the deployed app to the user before Sun Nov 8, collect feedback, and record
  it in `LOG.md`.

### Persona: day-trading statistics

The interviewee motivates the strategy with these figures:

```
┌──────────────────────────────────────────────────────────┐
│                     97% UNPROFITABLE                     │
│               (Lost money or broke even)                 │
└──────────────────────────────────────────────────────────┘
                             ▲
                             │  (Remaining 3% are profitable)
                             ▼
┌──────────────────────────────────────────────────────────┐
│ 3% PROFITABLE  (luck + skill; any profit over timeframe) │
│                                                          │
│ ┌──────────────────┐┌──────────────────────────────────┐ │
│ │   1% of ALL      ││   2% of ALL                      │ │
│ │   traders        ││   traders                        │ │
│ │                  ││                                  │ │
│ │ = 1/3 (≈33%) of  ││ = 2/3 (≈67%) of the profitable   │ │
│ │ the profitable   ││ group                            │ │
│ │ group            ││                                  │ │
│ │                  ││ Profitable, but NOT consistently │ │
│ │ CONSISTENTLY     ││ (likely luck)                    │ │
│ │ PROFITABLE       ││                                  │ │
│ └──────────────────┘└──────────────────────────────────┘ │
│  ◄──── 1/3 ────►     ◄────────────── 2/3 ─────────────►  │
└──────────────────────────────────────────────────────────┘
```

**Accuracy note:** 97/3/1 is a general rule of thumb, not a precise or worldwide statistic.
No global dataset of day traders exists; each study covers one market, time period, and
definition of "profit."

- **97% lose / 3% profit:** Brazil futures day traders active 300+ days, net of fees
  (Chague, De-Losso & Giovannetti, 2019). Loss rates are lower for casual traders and in
  bull markets (e.g. Jordan & Diltz, 2003: roughly a third of US day traders profitable in
  the late 1990s).
- **1% consistently profitable:** best supported. Fewer than 1% of Taiwanese day traders
  were predictably profitable after costs over ~15 years (Barber, Lee, Liu & Odean, 2020).

**Implications for the plan (to confirm with the user, not yet requirements):**
- The odds are the reason paper trading matters: a trader can find out which group they are
  in without risking real money. This supports the core scope in section 4.
- "Profitable" and "consistently profitable" are different things. Possible LiveView-only
  features: realized/unrealized P&L, and results tracked over time (per day or per session)
  so the user can tell skill from luck.

### Interview 1 (2026-10-30): John Daytrader's strategy

Full notes are in `LOG.md`. Summary of what they told us:

- **Edge:** do the opposite of retail. Retail clusters stop-losses just past obvious
  support/resistance; institutions push price through those levels to trigger the stops and
  get the liquidity they need to fill large orders.
- **Three-step framework:**
  1. **Liquidity sweep:** never buy a breakout or short a breakdown. Wait for price to breach
     an all-time high or key low, trigger stops, and trap retail on the wrong side.
  2. **4-hour supply/demand zone:** on the 4-hour chart, find the candle that started a
     violent, high-volume move and mark its full high-to-low range (the order block).
  3. **Execution:** when price pulls back into that zone, enter with a **limit order**. Hard
     **stop-loss** just past the sweep's swing high (risk ≈ 7% of the position). **Scale out
     50%** at the first opposing zone; let the other half run to deeper levels.
- **Example trade (QBTS short, $60,000):** limit entry at $19.13; risk capped at ≈ $4,200 by a
  hard stop (7% of $60,000); took 50% off at the target demand zone for ≈ $7,500 profit; the
  rest targeted deeper support. Thesis: a parabolic, speculative run on an unprofitable company
  that had swept its all-time high and re-entered a 4-hour supply zone.
- **Risk vs. emotion:** accept the loss before the order fills, treat each trade as a
  probability, never chase, wait for the limit price.

**Requirements this implies (decisions in section 4):**

| Interviewee needs | Today's plan | Gap |
|---|---|---|
| Limit-order entries | Market orders only | Resting orders that fill when a broadcast price crosses the limit |
| Hard stop-loss set at entry | None | Stop orders triggered by the price stream |
| Scale out 50% | Sell any quantity | Works already; a one-click "close half" is a convenience |
| Short selling | "Selling more than held" is an error | Separate Short / Cover actions |
| Risk known before the fill | Confirmation after the fill | Pre-trade preview: position size, $ at risk, % at risk |
| 4-hour candles and zones | Live quotes for 5 tickers only | Alpaca historical 4-hour bars (section 5, step I) |
| Trades high-beta names like QBTS | AAPL, AMZN, GOOGL, MSFT, TSLA | Alpaca poller for extra tickers (section 5, step B2) |

### Interview questions (answers go in `LOG.md`)
1. One shared demo portfolio, or separate accounts? *(open)*
2. Order types: market only, or limit/stop too? *(answered: limit entries, hard stop-losses,
   partial exits, and short selling)*
3. Starting cash? *(open; their example position was $60,000)*
4. How should dividends appear (cash credit, event feed, per-position history)? *(open; not
   mentioned in interview 1)*
5. What does "smooth" mean to you on the current React UI? What feels slow or jumpy? *(open)*
6. What would make this useful enough to come back to? *(open)*

**Follow-up questions from interview 1:**
7. Do you want the app to detect sweeps and draw 4-hour zones, or will you mark zones yourself
   and only need the orders?
8. How should shorts work in the simulation: any cash requirement or limit on size?
9. Which tickers do you need? Is QBTS required? (The current 5 are AAPL, AMZN, GOOGL, MSFT,
   TSLA.)
10. Should the 50% scale-out be a resting take-profit order, or a manual click?
11. Do you need a record of past trades with $ risked vs. $ made, to check whether you are
    consistently profitable?
12. Are simulated dividends still important to you?

## 3. Goals

**User goal:** a paper-trading simulator on Capstock's live price stream.

**Dev goals (mine):**
1. Learn LiveView fundamentals: mount/handle_event/handle_info, PubSub subscriptions,
   process-per-user model, failure modes.
2. Compare server-rendered LiveView with the existing React SPA on the same feature and
   backend, using measured numbers rather than impressions.

## 4. Scope

### Benchmark feature, built in both UIs
A buy/sell paper-trading panel. Both UIs must match this spec exactly so the comparison measures
the frontend, not different features.

- **Inputs:** ticker, quantity, buy/sell.
- **Fill:** market orders at the latest broadcast price.
- **Feedback:** order confirmation, updated position, updated cash.
- **Errors:** insufficient cash, selling more than held, unknown ticker.

Both UIs call one shared Elixir trading module. LiveView calls it from `handle_event`; React
reaches it through new API endpoints or channel messages.

The benchmark stays **market orders only** so it is small enough to build twice and compare
fairly. Interview-driven order types go in LiveView only (below). *(Proposed after interview 1;
confirm.)*

### LiveView only
- Read-only live prices page (`PricesLive`).
- **From interview 1, in priority order (proposed; confirm):**
  1. Limit-order entries (resting until a broadcast price crosses the limit).
  2. Hard stop-loss attached at entry.
  3. Pre-trade risk preview: position size, $ at risk, % at risk.
  4. Short / Cover actions. "Sell" keeps its benchmark meaning, so "selling more than held"
     is still an error.
  5. Take-profit / scale-out (e.g. close 50% at a target).
  6. Trade history with $ risked vs. $ made.
  7. 4-hour candles with marked zones. The data is available from Alpaca (section 5); this
     stays last because of time, not data.
- Simulated dividends (not mentioned in interview 1; lower priority until confirmed).

### Out of scope
- Real orders, brokers, or payment providers. Trading is simulated only.
- Placing orders through Alpaca's trading API, even in paper mode. Alpaca is used for market
  data only; fills, positions, and cash belong to Capstock's own trading module.
- Multi-node deployment (SQLite is single writer, single node).
- Replacing the React SPA. It keeps working throughout.

### Cut order if time runs short
1. Dividends → seeded data with a minimal display, or dropped if the interviewee confirms they
   don't need them.
2. 4-hour candles and zones (interview item 7, step I).
3. Staging Fly app.
4. Alpaca poller (step B2) → trade only the 5 Finnhub tickers. Cut only if John confirms QBTS
   isn't required (follow-up question 9).
5. Metrics → the core three only: first-load bytes, WebSocket bytes per tick, server memory
   per connected user.
6. Interview items 5–6 (take-profit, trade history).

Never cut: the shared trading module with tests, the LiveView trading panel, limit entries and
stop-losses (the core of the interviewee's workflow), the handover.

## 5. Technical approach

### Existing system (unchanged contract)
- Supervision tree (`:one_for_one`): Repo → Worker → Pruner → PubSub → Mock.Streamer → Endpoint.
- Worker polls Finnhub every 15s for 5 tickers (~20 of 60 calls/min on the free tier).
- Live flow: Worker → `save_price/2` → telemetry → `TelemetryHandler` →
  `PubSub.broadcast("stocks:live", {"new_price", payload})`.
- `/api` routes and `StockChannel` serve the React SPA and must keep working.

### Additions
| Step | Work | Notes |
|---|---|---|
| A | LiveView setup | App is JSON-only today. Add `phoenix_live_view`, `phoenix_html`, esbuild, tailwind, a browser pipeline, root/app layouts. `/api` stays untouched. |
| B | `PricesLive` | Subscribes to `"stocks:live"`. No new polling. |
| B2 | Alpaca poller | New supervised GenServer, same pattern as the Worker (Req + timer, injected deps). Polls Alpaca's multi-symbol latest-trades endpoint (IEX feed) for tickers Finnhub doesn't cover (e.g. QBTS) and broadcasts to `"stocks:live"` in the **same payload format**, so consumers can't tell the sources apart. |
| C | Trading module | Plain functions + Ecto schemas (portfolio cash, positions, orders). Integer cents / `Decimal`, never floats. Tests first. |
| D | Process design | Decide after C: where the latest price lives (DB lookup vs. a cache fed by `"stocks:live"`), how concurrent orders on one portfolio are serialized, and **which process watches the price stream to trigger resting limit/stop orders** (it must not live inside a LiveView, or orders die when the tab closes). Trade-offs recorded in `LOG.md`. |
| E | LiveView trading panel | Calls the trading module from `handle_event`. |
| F | React trading panel | API endpoints or channel messages here; React UI in the separate repo. |
| G | Interview-driven orders (LiveView) | Limit entries, stop-losses, risk preview, then Short/Cover and take-profit (section 4). Trading-module functions get tests first, same as C. |
| H | Dividends | First check what Finnhub's free tier provides; fall back to seeded data. |
| I | 4-hour chart (stretch) | Fetch 4-hour bars from Alpaca's historical **SIP** feed (full-market volume, which zone detection needs), cache them in the DB, render in LiveView. Never fetched per page view. |

### Data sources
Decided 2026-10-30 after testing the free Alpaca paper-account key (results in `LOG.md`).

| Source | Used for | Free-tier facts (tested) |
|---|---|---|
| Finnhub (existing Worker) | Live quotes for AAPL, AMZN, GOOGL, MSFT, TSLA | 60 calls/min, one call per ticker; ~20/min used |
| Alpaca market data, IEX feed | Live prices for extra tickers (step B2) | 200 calls/min; one request covers many tickers. IEX is one exchange (~7% of QBTS volume in a test bar), so prices are close to, not identical to, the full market |
| Alpaca market data, SIP feed | Historical 4-hour bars (step I) | Recent SIP trades are blocked (403); SIP bars, history back to at least Jan 2024, are allowed. Request with an `end` at least 15 minutes in the past to be safe |

- **One live source per ticker.** Two feeds for the same ticker would fight over the latest price.
- The Finnhub Worker is not changed, because the React SPA depends on it.
- **Later option (after Nov 8):** move the 5 Finnhub tickers to Alpaca too, for one source and
  one request per tick.
- Polling, not Alpaca's WebSocket stream: it reuses the Worker's pattern; a WebSocket client
  adds a dependency, reconnect logic, and tighter free-tier connection limits.
- Keys come from env vars `ALPACA_KEY_ID` and `ALPACA_SECRET` (`.env` locally, git-ignored;
  `fly secrets set` in production). Never committed or logged.

### Constraints
- No per-user or per-LiveView Finnhub or Alpaca calls; derive everything from the broadcast
  stream or DB. The Alpaca poller at a 15s interval uses ~4 of 200 calls/min.
- GenServers stay testable via injected deps (`now_fn`, `test_pid`, `schedule_timer`).
- Known issues listed in `CLAUDE.md` (Worker `async_stream` timeout, TelemetryHandler detach,
  PubSub start order, `StockChannel` intercept) are not made worse. They are fixed only as
  planned tasks.

## 6. Workflow

- **Branch:** all Artifact 4 work happens on `liveview`. `main` stays deployable.
- **Commits:** small, conventional-style messages (`feat:`, `fix:`, `test:`, `docs:`).
- **Merging:** I open a PR from `liveview` to `main` and merge it myself after the checks pass.
- **Before every commit:** `mix format`, `mix compile --warnings-as-errors`, `mix test`.
- **React changes:** a matching branch in the React repo, merged when the API side is on `main`.
- **Deploys:** production stays one Fly app (`capstock-backend`) serving `/api`, channels, and
  LiveView. Optional staging app (e.g. `capstock-live`) runs with the Worker and the Alpaca
  poller disabled, `Mock.Streamer` on, and its own SQLite.
- **Log:** append a dated `LOG.md` entry after each session: what was planned, what changed and
  why, user feedback, and LiveView vs. React observations.

## 7. Metrics (dev goal 2)

Both UIs run against the same backend and price stream. Before each measurement, I record a
prediction in `LOG.md`; afterwards, the result and the gap.

| Metric | How |
|---|---|
| First load: JS bundle, bytes transferred, time until prices appear | DevTools Network, Lighthouse |
| Per-update cost: WebSocket bytes per price tick | DevTools → Network → WS → Messages |
| Interaction latency: click Buy → confirmation visible | Normal and throttled network |
| Server cost per user | `Process.info(pid, :memory)`, LiveView vs. channel process |
| Client cost | DevTools Performance (CPU, memory) |
| Developer cost | Lines changed and hours to build the trading panel in each UI |

## 8. Schedule

| Date | Milestone |
|---|---|
| Fri Oct 30 – Sat Oct 31 | `PLAN.md`, `LOG.md`, commit `CLAUDE.md`, create `liveview` branch. Interview 1 done; send follow-up questions 7–12. Start LiveView setup (A). |
| **Sun Nov 1** | **Check-in:** portfolio card showing progress; plan and log in the repo. |
| Mon Nov 2 – Tue Nov 3 | `PricesLive` (B), Alpaca poller (B2). Trading module with tests (C), process design (D). |
| Wed Nov 4 | LiveView trading panel (E). |
| Thu Nov 5 | React trading panel (F). |
| Fri Nov 6 | Limit entries, stop-losses, risk preview (G). |
| Sat Nov 7 | Metrics. Deploy, hand over to the user, apply feedback. Dividends (H) only if time remains. |
| **Sun Nov 8, 11:59 PM** | **Due:** final `LOG.md` entry, portfolio card with link and reflection, Canvas submission. |

## 9. Risks

| Risk | Mitigation |
|---|---|
| Interview answers expand scope (happened in interview 1: limit/stop orders, shorts, 4-hour zones) | Benchmark stays market-only; new order types are LiveView-only and prioritized; apply the cut order in section 4. |
| Resting orders miss a fill (price gaps past a stop between 15s ticks, or the trigger process crashes) | Fill at the first broadcast price past the trigger, and say so in the UI; the trigger process is supervised and reloads open orders from the DB on restart. |
| Adding LiveView breaks `/api` or the React SPA | Separate browser pipeline; run existing API/channel tests on every change. |
| Finnhub or Alpaca rate limit | No per-user calls; all UI data comes from the broadcast stream or DB. Finnhub ~20/60 per min, Alpaca ~4/200. |
| Alpaca poller crashes or Alpaca is down | Supervised separately from the Worker (`:one_for_one`), so Finnhub tickers keep updating; extra tickers show their last price as stale. |
| Prices from two sources (IEX vs. Finnhub) aren't directly comparable | One source per ticker; the UI can label the source. Acceptable for paper trading. |
| Market closed during the demo | `Mock.Streamer` provides prices outside market hours. |
| Solo time budget (16–24 h) | Daily `LOG.md` check against this schedule; cut early, not on Nov 8. |

## 10. Definition of done

- The trading panel works in both UIs to the spec in section 4, backed by a tested trading module.
- `PricesLive` is deployed, plus at least limit entries and stop-losses from interview 1, with
  any other confirmed interview features that fit.
- The user has seen the finished work, and their feedback is in `LOG.md`.
- `PLAN.md` and `LOG.md` are in the repo; metrics are recorded with predictions and results.
- The portfolio card has a title, link, and reflection, and the link is submitted on Canvas.
