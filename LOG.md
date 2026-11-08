# LOG.md — Capstock LiveView (Artifact 4)

Dated record of what was planned, what changed, and why. Newest entries at the bottom.
The agreed plan lives in `PLAN.md`.

---

## 2026-10-30 — Kickoff, plan, interview 1

### Planned
- Read the Artifact 4 assignment sheet and `CLAUDE.md`; check the repo's starting state.
- Write `PLAN.md` and start this log.
- Record interview 1 and update the plan from it.

### Done
- **Starting state:** no `PLAN.md` or `LOG.md`; `CLAUDE.md` not yet committed; no `liveview`
  branch; app is JSON-only (no `phoenix_live_view`, `phoenix_html`, esbuild, or tailwind in
  `mix.exs`). Remote branches `mtpbranch` (Jul 25) and `tinbranch` (Aug 3) predate Artifact 4.
- **Team:** I received permission to do Artifact 4 solo and own the full project. Recorded in
  `PLAN.md` §1.
- **`PLAN.md` created:** scope (benchmark trading panel in both UIs, LiveView-only features),
  technical approach, workflow, metrics, schedule, risks, definition of done.
- **Persona statistics added** to `PLAN.md` §2 (97% unprofitable / 3% profitable / 1%
  consistently profitable, with sources and an accuracy note).
  - To check: the Taiwan "fewer than 1% predictably profitable" finding may be Barber, Lee, Liu
    & Odean (2014), *The Cross-Section of Speculator Skill*, not 2020.
- **Interview 1 held and recorded** (transcript below). I (Daniel) was the interviewer; John
  Daytrader was the interviewee.
- **User identity:** the interviewee asked to remain anonymous, so they are referred to by the
  pseudonym "John Daytrader" in the repo. Real name and contact details are not stored here.

### Interview 1 — transcript (John Daytrader)

Interviewer: Daniel (me). Interviewee: John Daytrader (pseudonym).

> **Daniel (interviewer):** "Most retail day traders lose money. How do you exploit institutional order flow and
> liquidity traps to build a consistent edge, and what specific rules govern your entries,
> stop-outs, and profit scaling?"
>
> **John (interviewee):** "The reality is that 99% of day traders fail, so my entire edge comes down to
> doing the exact opposite of what the retail crowd does.
>
> Retail traders operate predictably: they look at a key support or resistance level and
> cluster their stop-losses right past it. But institutional players trade with hundreds of
> millions of dollars. They can't just hit market buy or sell without causing massive slippage
> because there simply isn't enough counter-liquidity at that price. So, they engineer it. They
> push price past those obvious levels to trigger everyone's stop-losses, forcing retail into
> panic sells or forced buys, which creates the massive pool of shares institutions need to
> fill their own orders.
>
> To exploit that, I use a three-step framework:
>
> Wait for the Liquidity Sweep: I never buy a breakout or short a breakdown. I wait for price to
> aggressively breach an all-time high or a key low, trigger the stops, and trap retail traders
> on the wrong side.
>
> Identify 4-Hour Supply and Demand: Retail doesn't move the market; institutions do. I go to
> the 4-hour chart, find the candle that initiated a violent, high-volume move, and mark its
> entire high-to-low range. That candle marks the institutional order block.
>
> Execution, Stops, and Scaling: Once price sweeps liquidity and pulls back directly into that
> 4-hour zone, I set a limit order to enter. My stop-loss is placed strictly above the recent
> swing high from the sweep—capping risk to roughly 7%. When the move plays out, I never get
> greedy: I scale out 50% of the position at the first major opposing demand zone to lock in
> profits and eliminate downside risk, leaving the remaining half to run toward the deeper
> swing lows."
>
> **Daniel (interviewer):** "Describe a high-stakes scenario where you put significant personal capital on the
> line. What was your analytical thesis, how did you handle risk versus emotion under pressure,
> and what was the outcome?"
>
> **John (interviewee):** "A prime example was taking a $60,000 short position on QBTS.
>
> My thesis blended structural market mechanics with behavioral sentiment. Long term, I
> actually believe in quantum computing—I previously rode QBTS from $4 up to $18—but the recent
> parabolic surge to a $5.3 billion market cap was driven by pure speculative spillover from
> the AI bubble. The company was still net-unprofitable. Once the chart swept its all-time
> highs and re-entered a 4-hour supply zone, I knew buyers were primarily retail momentum
> chasers. Speculators panic the moment green turns red, and that panic provides immense
> downside fuel.
>
> Putting $60,000 into a high-beta, volatile stock will always make you nervous. To neutralize
> the emotion, I removed discretion from the trade:
>
> I accepted the downside before the order even filled, capping my risk at around $4,200 with
> a hard stop-loss.
>
> I treated the setup strictly as a game of probabilities rather than an emotional bet.
>
> I refused to chase the market, waiting patiently for my limit order at $19.13 to get hit.
>
> The discipline paid off. The price rejected the supply zone immediately and dropped straight
> into my target demand level. Following my plan, I took 50% of the position off the table to
> lock in a $7,500 profit. That banked a solid return, neutralized capital risk, and gave me a
> free hand to let the rest of the position target deeper support."

### What interview 1 changed in the plan, and why
| Change (`PLAN.md`) | Why |
|---|---|
| §2: interview summary, requirements gap table, interview question status, follow-up questions 7–12 | Record what the user needs vs. what was planned. |
| §4: benchmark stays market-only; limit entries, stop-losses, risk preview, Short/Cover, take-profit, trade history, 4-hour zones added as LiveView-only, in priority order | The interviewee's workflow depends on limit entries and hard stops. Keeping the benchmark small keeps the LiveView vs. React comparison fair and buildable twice. |
| §4: "Sell" keeps its meaning; shorting is a separate Short / Cover action | Shorting would otherwise conflict with the benchmark's "selling more than held" error. |
| §4: cut order revised; dividends moved down | Dividends weren't mentioned in interview 1; limit/stop orders were central. |
| §5: step D now includes the process that triggers resting orders; new step G (interview-driven orders); dividends became H; 4-hour candle data question added | Resting orders need a supervised process watching `"stocks:live"`, outside any LiveView. 4-hour candles may not be possible from current data or Finnhub's free tier. |
| §8: Fri Nov 6 → limit/stop/risk preview; dividends only if time remains Sat Nov 7 | Make room for the interviewee's core needs. |
| §9–§10: new risk for missed fills; definition of done requires limit entries and stop-losses | Follows from the above. |

### Interview answers so far
- Q2 order types: **answered** (limit entries, hard stop-losses, partial exits, short selling).
- Q3 starting cash: open (example position was $60,000; stated risk ≈ $4,200 = 7%).
- Q1 accounts, Q4 dividends, Q5 "smooth", Q6 what brings them back: open.
- Interviewee's own figure is "99% of day traders fail," vs. the 97/3/1 figures in `PLAN.md`
  §2. Both are rough estimates; noted, not resolved.

### Second data source: Alpaca (market data only)
Finnhub alone can't cover John's needs (more tickers like QBTS, 4-hour candles) without
paying. I set up a free Alpaca paper account and tested what its API key can do.

**Setup**
- Keys in `.env` (git-ignored) as `ALPACA_KEY_ID` and `ALPACA_SECRET`. Fixed a misspelling
  (`ALPACA_SECRETE`). The values are quoted in `.env`, so loaders must strip the quotes.
- Paper account check (`GET paper-api.alpaca.markets/v2/account`): HTTP 200, ACTIVE, $100,000
  cash, $400,000 buying power (4× margin), shorting enabled.

**Market-data tests (`data.alpaca.markets`, free tier)**
| Test | Result |
|---|---|
| Latest trades for AAPL, QBTS, TSLA in one request, IEX feed | 200 (QBTS $10.645) |
| Rate limit header | 200 requests/min |
| Latest trades, SIP (full-market) feed | 403 "subscription does not permit querying recent SIP data" |
| 4-hour bars, QBTS, IEX feed | 200 |
| 4-hour bars, QBTS, SIP feed, historical | 200, including today's bars |
| 4-hour bars from Jan 2024 | 200, so at least ~2 years of history |
| IEX vs. SIP volume, QBTS 4-hour bar on Oct 27 16:00 UTC | 425,912 vs. 5,732,796 (IEX ≈ 7%) |

**Decisions (recorded in `PLAN.md` §5 "Data sources")**
| Decision | Why |
|---|---|
| Alpaca for market data only; no orders through Alpaca's trading API | Fills, positions, and cash stay in Capstock's own trading module: it's the benchmark and the core OTP learning, and `CLAUDE.md` rules out brokers. |
| Keep the Finnhub Worker unchanged for the 5 current tickers | The React SPA depends on it; rewriting it costs schedule time. |
| New step B2: Alpaca poller for extra tickers (e.g. QBTS), IEX feed, broadcasting to `"stocks:live"` in the same payload format | One request covers many tickers (~4 of 200 calls/min at 15s). Consumers (`PricesLive`, the order-trigger process, React) don't need to know the source. |
| One live source per ticker | Two feeds for one ticker would fight over the latest price. |
| New step I: 4-hour bars from historical SIP, cached in the DB | Resolves the 4-hour data question. SIP because John's zones depend on high-volume candles and IEX has ~7% of the volume. Still a stretch goal for time reasons. |
| Polling, not Alpaca's WebSocket stream | Same pattern as the existing Worker; a WebSocket client adds a dependency, reconnect logic, and tighter connection limits. |
| Later option: move all tickers to Alpaca | One source, one request per tick, no 60/min ceiling. After Nov 8 if at all. |

Also updated in `PLAN.md`: requirements table (§2), out of scope (§4: no Alpaca orders), cut
order (§4: Alpaca poller cut only if QBTS isn't needed), staging disables the Alpaca poller
(§6), schedule (§8: B2 on Mon–Tue Nov 2–3), risks (§9).

### Open decisions (mine to confirm)
- Benchmark panel stays market-only; new order types LiveView-only.
- Priority order of interview-driven features (`PLAN.md` §4).
- Which extra tickers the Alpaca poller covers: waiting on John's answer to follow-up question 9.

### Next
- Send follow-up questions 7–12 to John Daytrader.
- Create the `liveview` branch; commit `CLAUDE.md`, `PLAN.md`, `LOG.md`.
- Start LiveView setup (step A).
- Add `ALPACA_KEY_ID` / `ALPACA_SECRET` to Fly secrets before the Alpaca poller (B2) deploys.
- Portfolio card for the Sun Nov 1 check-in.

### LiveView vs. React observations
- None yet.

---

## 2026-10-31 — Branch, push, step A folder structure

### Planned
- Create the `liveview` branch, commit and push the docs (for the Nov 1 check-in).
- Set up the folder structure for step A (LiveView setup).

### Done
- **Branch:** created `liveview` from `main`; committed `CLAUDE.md`, `PLAN.md`, `LOG.md`
  (`cb77166`) and pushed to `origin/liveview`.
- **`CLAUDE.md`:** added Alpaca context (market data only, key names, free-tier limits, one
  live source per ticker; staging disables the Alpaca poller).
- **Renamed `lib/stock_fetcher_Web` → `lib/stock_fetcher_web`** and
  `test/stock_fetcher_Web` → `test/stock_fetcher_web` with `git mv` (history kept).
  - Why: Phoenix generators write to `stock_fetcher_web/`, which would have created a second
    folder next to the capitalized one; on the Windows copy (case-insensitive) the two would
    collide.
  - No code changes: nothing referenced the path, and module names don't depend on folders.
- **New empty folders for step A** (`.gitkeep` in each): `assets/{js,css,vendor}`,
  `lib/stock_fetcher_web/components/layouts`, `lib/stock_fetcher_web/live`,
  `test/stock_fetcher_web/live`, `priv/static`.
- **Checks:** `mix compile --warnings-as-errors` clean; `mix test` 42 tests, 0 failures, before
  and after the rename.

### Next (step A, mine to write)
- `mix.exs`: `phoenix_live_view`, `phoenix_html`, esbuild, tailwind deps and asset aliases.
- `config/`: esbuild and tailwind config; dev watchers.
- `lib/stock_fetcher_web.ex` (`use StockFetcherWeb, :live_view` etc.), `core_components.ex`,
  `layouts.ex`, root/app layouts.
- Router: browser pipeline next to the existing `/api` pipeline (`/api` unchanged).
- Endpoint: LiveView socket and static assets.
- `.gitignore`: `/priv/static/assets/`.
- Reference for generated files: a throwaway `mix phx.new` at **1.7.24** (matches `mix.lock`;
  1.8 uses Tailwind v4 + daisyUI).

### Notes
- The Windows copy may not handle the case-only rename on pull; re-clone it if it does not.

### LiveView vs. React observations
- **"Hydration" (first data load) works differently in each UI.**
  - Two meanings of the word: *data hydration* (client starts empty and fetches what it needs
    to render; this repo's meaning: `get_hydrated_prices/3`, `hydrate_watchlist/3`,
    `HydrationLimiter`) vs. *SSR hydration* (React/Next.js: client JS attaches to HTML the
    server already rendered).
  - **React SPA:** load JS bundle → render empty shell → separate HTTP request to
    `/api/stocks` → render → join the channel. The data fetch is its own round trip, which is
    why it needed a rate limiter.
  - **LiveView:** no separate data call. `mount/3` loads the data on the server and it ships
    inside the first HTML. When the WebSocket connects, `mount/3` runs again in the new
    LiveView process and loads the data a second time.
  - **Cost on the LiveView side:** the double load. Wrapping the query in `connected?(socket)`
    saves one query but leaves the first HTML without prices (trades first-paint content for
    less DB work). Decision pending in `PricesLive` TODO(2).
  - **Metric impact:** "time until prices appear" should favor LiveView (prices can be in the
    first response; React waits for bundle + API call). Record a prediction before measuring.

### Later on 2026-10-31 — Step A deps and a security fix

**Deps for step A** (`49aaffd`)
- Added `phoenix_html`, `phoenix_live_view`, `phoenix_live_reload` (dev), `esbuild` and
  `tailwind` (dev runtime only). Resolved: LiveView **1.2.13** (supports Phoenix `~> 1.7.0`),
  phoenix_html 4.4.0, phoenix_live_reload 1.7.0, esbuild 0.10.1, tailwind **0.5.2**.
- Review notes, still to add when needed:
  - `aliases: aliases()` with `assets.setup` / `assets.build` / `assets.deploy`, before the
    first asset build and before deploying.
  - `{:lazy_html, ">= 0.1.0", only: :test}` before the first LiveView test: LiveView 1.1+
    uses it (not Floki) for `Phoenix.LiveViewTest`, and lists it as optional, so nothing warns.
  - Dockerfile has no asset step: needs `COPY assets` and `mix assets.deploy` before
    `mix release`, or production pages get no CSS/JS.
  - Optional: tighten constraints to `"~> 1.2"` / `"~> 0.5"` to match what resolves.

**Tailwind v3 vs. v4 (open decision)**
- The `tailwind` package has no Phoenix dependency, so v4 works on Phoenix 1.7.24. Package
  0.3+ assumes v4: `version: "4.3.0"`, `--input`/`--output` args, no `tailwind.config.js`;
  config moves into `app.css` (`@import "tailwindcss" source(none);` plus `@source` lines).
- Trade-off: phx_new 1.7.24's generated files assume v3 (`core_components.ex` icons come from a
  JS plugin in `tailwind.config.js`); phx_new 1.8's v4 files bring daisyUI and 1.8 layouts.
- Leaning: v4 with a few hand-written components instead of copying all of
  `core_components.ex`, no daisyUI. Fallback if time is short: v3 (`~> 0.2.0`) + copy 1.7.24.

**Security fix** (`1b23b90`, lockfile only, kept separate so it can be cherry-picked to `main`)
- `mix deps.get` reported advisories against versions already locked on `main` (so production
  is affected), not introduced by the LiveView deps:
  - bandit 1.12.1 → 1.14.1: 15 advisories, mostly HIGH (HTTP/2 and HTTP/1.1 DoS, WebSocket
    fragment-limit bypass).
  - mint 1.9.3 → 1.11.0: 6 HIGH/MEDIUM (memory-exhaustion DoS, response smuggling).
  - decimal 3.1.1 → 3.2.0: 1 MEDIUM. plug_crypto 2.1.1 → 2.2.1: 1 MEDIUM (CVE-2026-105963).
  - Transitive: castore, hpax, thousand_island.
- Verified: no advisories reported; compile clean; 42 tests pass; dev server returned 200 on
  `/api/health` and 101 on the `/socket/websocket` upgrade (React's channel path).
- Lesson: my first check cut the `mix deps.get` output at 25 lines and missed most advisories.
  Read the whole advisory list.
- **Not yet in production.** To ship: cherry-pick `1b23b90` onto `main`, deploy.

**Next**
- Decide Tailwind v3 vs. v4; then esbuild/tailwind config, browser pipeline, endpoint socket.
- Ship the security fix to production.

**Decisions (end of 2026-10-31)**
- **Tailwind v4.** Hand-write the few components needed (prices table, trading form, flash)
  instead of copying all of `core_components.ex`; no daisyUI. Recorded in `PLAN.md` step A.
- **No deploy until a big change ships.** Production will be deployed with the first basic
  LiveView release, and the security fix (`1b23b90`) goes out with it. Until then production
  keeps the vulnerable Bandit/Mint versions; accepted risk, recorded in `PLAN.md` §9.

### Later on 2026-10-31 — Step A: LiveView plumbing and `PricesLive` scaffold

**Why the agent wrote this part:** I had not written LiveView before. Split agreed: the agent
writes the plumbing a generator would normally produce (with "why" comments); I write the
first real LiveView (`PricesLive` TODOs 1–5).

**Plumbing added**
| File | What / why |
|---|---|
| `mix.exs` | `assets.setup` / `assets.build` / `assets.deploy` aliases; `lazy_html` (test) for `Phoenix.LiveViewTest`. My earlier `~> 1.2` / `~> 0.5` constraints kept. |
| `config/config.exs` | esbuild 0.25.0 profile (`NODE_PATH` → `deps/` so `import "phoenix_live_view"` resolves); Tailwind **4.3.0** profile (`--input`/`--output`, no JS config); LiveView signing salt. |
| `config/dev.exs` | Watchers (esbuild/tailwind rebuild on save) and live-reload patterns for `live/` and `components/`. |
| `endpoint.ex` | Cookie session options; `/live` LiveView socket; `Plug.Static` for `priv/static/assets`; dev `LiveReloader` + `CodeReloader`; `Plug.Session` before the router. React's `/socket`, Corsica, and parsers unchanged. |
| `router.ex` | `:browser` pipeline (session, live flash, root layout, CSRF, secure headers) and `live "/prices", PricesLive`. `:api` and its scopes untouched. |
| `lib/stock_fetcher_web.ex` | `use StockFetcherWeb, :live_view` / `:html` (shared imports, `~p` verified routes). |
| `components/layouts.ex`, `layouts/root.html.heex` | Page shell: CSRF meta tag, CSS, JS. No app layout or flash yet (needed for step E). |
| `assets/css/app.css` | Tailwind v4: `@import "tailwindcss" source(none)`, `@source` for `assets/` and `lib/stock_fetcher_web`, `phx-*-loading` variants. |
| `assets/js/app.js` | ~10 lines: connect the `LiveSocket` with the CSRF token. All the client JS a basic LiveView needs. |
| `.gitignore` | `/priv/static/assets/`, `/priv/static/cache_manifest.json`. |

**Scaffold for me:** `live/prices_live.ex` runs (heading + "Waiting for prices…") with TODOs:
(1) subscribe to `"stocks:live"` only when `connected?/1`, and explain why in this log;
(2) load starting prices from the DB (`get_hydrated_watchlist/0` vs. a new `latest_prices/0`);
(3) `handle_info({"new_price", payload}, socket)`; (4) render the table in HEEx;
(5) a test that broadcasts a fake price. `test/.../prices_live_test.exs` has the first test.

**Verified**
- `mix format`, `mix compile --warnings-as-errors` clean; `mix test` **43 tests, 0 failures**.
- Real server: `/prices` 200 HTML; `/assets/css/app.css` and `/assets/js/app.js` 200;
  `/api/health`, `/api/stocks` 200 JSON (unchanged); `/socket` (React) and `/live` WebSockets
  101; live-reload socket 101.
- Installed `inotify-tools` (WSL) so live reload works; confirmed the browser refreshes on save.
- I changed the heading to "Live Prices", which broke the test's case-sensitive `=~ "Live
  prices"`; test updated to match.

**Learned so far**
- `mount/3` runs twice: a static HTTP render (full HTML for first paint), then a connected
  mount in a new, long-lived LiveView process when `/live` connects. The server log shows both
  (`Processing with ... Pipelines: [:browser]`, then `CONNECTED TO Phoenix.LiveView.Socket` +
  `MOUNT`). My answer to *why* subscribe only when connected: If subscribe happens on the first mount run, then the subscription would be useless, because the first mount call is a one-shot call, not a persistent connection. The process can't push to the browser, and in case it stays alive (HTTP keep-alive), unread messages pile up in its mailbox.

**Notes / open items**
- Dev `app.js` is 1.15 MB served (inline sourcemap; 320 KB without). Bundle-size metric must
  use the minified `mix assets.deploy` build.
- Dockerfile still lacks the asset step (`COPY assets`, `mix assets.deploy` before
  `mix release`). Required before the first LiveView deploy.
- `/favicon.ico` 404s in dev (harmless; add one to `priv/static/`).

### Later on 2026-10-31 — `PricesLive` TODO 1 done, TODO 2 designed

**TODO 1: subscribe only when connected** (`5f755f6`)
- Added `if connected?(socket), do: Phoenix.PubSub.subscribe(StockFetcher.PubSub, "stocks:live")`
  to `mount/3`. My "why" is under *Learned so far* above.
- My first attempt put the `if` *after* `{:ok, assign(...)}`. Elixir returns the last expression,
  so `mount/3` returned `nil` (dead render) or `:ok` (connected) and the test failed with
  `invalid result returned from ... mount/3. Expected {:ok, socket}`. The compiler doesn't warn
  about a discarded tuple, so only `mix test` caught it. Lesson: side effects first, return
  tuple last.
- My first LOG edit didn't land: unsaved/wrong copy. Edit the WSL copy only.

**Editor errors in `mix.exs` (not a project problem)**
- Neovim's ElixirLS keeps its own build in `.elixir_ls/build/`. After the security bump it still
  had `hpax 1.0.4` / `thousand_island 1.5.0` while `mix.lock` needs `1.1.0` / `1.6.0`. Its deps
  check failed before it could recompile, so it stayed broken on every restart (seen in
  `~/.local/state/nvim/lsp.log`). Fix: `:LspStop`, `rm -rf .elixir_ls/build`, `:LspStart`.
- Version mismatch to keep in mind: ElixirLS runs Elixir 1.19.5 (mise); the terminal `mix` is
  1.18.3 (`/usr/bin`). Editor warnings may differ from `mix compile`. Pin one version if it
  gets confusing.

**TODO 2: design decisions (code not written yet)**
- **New `StockFetcher.latest_prices/0` instead of reusing `get_hydrated_watchlist/0`.** My first
  reason was "backward compatible with React", but reusing the old function wouldn't break React
  either. The real reasons:
  1. It only looks back 12h, so on weekends (market closed since Friday) it returns empty lists
     and the page would show nothing. The latest row with no cutoff shows Friday's close.
  2. It loads up to 12h of rows per ticker and LTTB-downsamples them, just to show one price.
- **Query: one `group_by ticker` + `max(id)` subquery, not one query per ticker.** Main reason:
  it returns every ticker in the table, so B2's Alpaca tickers (QBTS) show up without changing a
  hard-coded list. Fewer queries is a minor win with SQLite (in-process, no network round trip).
- **`max(id)`, not `max(inserted_at)`.** In production each ticker gets one row per 15s, so no
  ties. But `inserted_at` is `:utc_datetime` (whole seconds), and the test saves several rows in
  the same second, so ordering by time would make the test flaky. Auto-increment `id` always
  increases with each insert.
- **Load in both mounts (dead render + connected), subscribe only when connected.** Server-
  rendered first paint is LiveView's main advantage over the React SPA; loading only when
  connected would give it up. A DB read leaves nothing behind in the one-shot process, unlike a
  subscription. Order matters: subscribe first, then load, so a tick between the two isn't lost.
- **`@prices` holds the broadcast shape `%{ticker, price, timestamp}`** for consistency. The
  broadcast shape can't change (React and `Mock.Streamer` depend on it), and converting once per
  mount is cheaper than converting every tick. DB rows get converted in `mount/3`
  (`inserted_at` → `timestamp`); `handle_info` stores payloads as they arrive.
- I had confused Ecto's `timestamps()` macro (adds `inserted_at` and `updated_at`) with the
  payload's `timestamp:` key. That key is hand-built in `TelemetryHandler` (line 39) from
  `inserted_at`.

**How I now understand the two frontends**
- React: `index.html` is an empty shell → download and run the JS bundle → render a loading
  state → `GET /api/stocks` (JSON) → React renders in the browser → channel ticks send JSON and
  React diffs its virtual DOM in the browser.
- LiveView: `GET /prices` → server runs `mount/3` + `render/1` in a one-shot process → browser
  paints full HTML with no JS run → `app.js` (deferred) loads and opens `/live` → join sends the
  signed `data-phx-session` token → server starts a long-lived process, mounts again, sends
  statics + dynamics → each tick the server sends only changed dynamics (values, e.g.
  `{"0": "190.10"}`) and the JS patches the DOM.
- Where the diffing happens: LiveView works out changes on the server and sends a few bytes;
  React gets the data and works out changes in the browser.
- On reconnect (sleep, Wi-Fi drop, deploy), LiveView starts a new process and re-runs
  `mount/3`, and old assigns are gone. Fine for prices (reloaded from the DB); the trading panel
  must keep cash and positions in the trading module/DB, never only in assigns. React keeps its
  state in the browser across a socket drop.

**Prediction (first-load metric, before measuring)**
- LiveView shows prices at first paint, before `app.js` runs. React shows them only after the
  bundle downloads and `/api/stocks` returns. Loading only on the connected mount would delay
  LiveView by about the JS load + WebSocket join time. The extra query costs ~1 ms server-side
  (54 µs measured on the empty dev DB; prod has more rows and no index).

**Found while reading code (later)**
- `stock_prices` has no index on `ticker` or `inserted_at`; both query styles scan the table.
  Fine while the Pruner keeps it small.
- `StockPrice.price` is a `:float` column. The TODO 3 scaffold comment saying "Decimal from the
  DB" is wrong: the trading module (step C) must convert to Decimal/integer cents itself.
- Dev DB has 0 rows (the Worker only saves during market hours; `Mock.Streamer` broadcasts
  without saving), so the initial load can't be seen in the browser until Monday. The test is
  the proof.

**Next (mine)**
- Write `latest_prices/0` (+ `@doc`) and a `describe "latest_prices/0"` test; load and convert in
  `mount/3`; then TODO 3 (`handle_info`), TODO 4 (table), TODO 5 (broadcast test).

## 2026-11-01 — Check-in, `PricesLive` finished (step B), trading module draft (step C)

### Check-in (Canvas, Nov 1)
- Portfolio card updated (`portfolio-spa/src/data/artifacts.js`, deployed to GitHub Pages):
  new title/description, status "In progress (check-in Nov 1)", a progress reflection, and the
  link changed to `.../tree/liveview`. `PLAN.md`/`LOG.md`/`CLAUDE.md` exist only on `liveview`,
  not `main`, so a repo-root link would have shown no plan or log. The old card also said
  "Built with a team", which contradicted the solo plan.
- Pushed `liveview` so the link shows the current log. Portfolio link submitted on Canvas.

### Work split from today (time is short)
- I write the LiveView parts with skeletons from the agent; the agent drafts the trading module,
  React panel, and Dockerfile/deploy, and I review each and explain it back here.
- For speed, the agent wrote TODO 3–5 today at my request (steps below), so the LiveView
  developer-cost metric counts TODO 1–2 as mine and TODO 3–5 as agent-written.

### TODO 2: initial load (`04854e5`, mine)
- Added `StockFetcher.latest_prices/0` (`@spec latest_prices() :: [%StockPrice{}]`): a
  `group_by ticker` + `max(id)` subquery, then the full rows sorted by ticker. `mount/3` loads
  it on both renders and converts each row to `%{ticker, price, timestamp}`.
- Bugs I made, and what caught them:
  1. `select: s.id` instead of `max(s.id)`. SQLite accepts a bare column in a grouped query and
     returns *some* row's id (Postgres would reject it), so tests would likely have passed
     while the query was wrong.
  2. My test treated the result as a map (`result.rows`, `result.tickers`) with made-up fields;
     `Repo.all` always returns a list (`[]` when empty, never `nil`). Habit: `dbg/1` or
     `iex -S mix` to see the real shape before writing asserts; a `@spec` shows it on hover (`K`).
  3. `timestamp: row.timestamp`: `StockPrice` has no `timestamp` field (it's `inserted_at`),
     so mount would raise `KeyError` as soon as the DB had one row. Tests passed because the
     test DB was empty and `Map.new([], fun)` never calls `fun`. Added a mount test that saves
     a row first.
- Lesson from all three: green tests only cover the paths they execute.
- Correction: LiveView without `handle_info/2` does **not** crash on an unexpected message; it
  logs at debug level (`phoenix_live_view/channel.ex:595`). It crashes only when `handle_info`
  exists and no clause matches.

### TODO 3–5: written by the agent (my request); steps it took
1. **TODO 3, `handle_info({"new_price", payload}, socket)`:** checked that `"new_price"` is the
   only message on `"stocks:live"` (grep for `broadcast`), and that both producers
   (`TelemetryHandler`, `Mock.Streamer`) send `id, ticker, price, timestamp`. `Map.take` keeps
   the three keys so broadcast entries match the mount shape, then
   `update(socket, :prices, &Map.put(&1, price.ticker, price))`.
2. **TODO 4, table in `render/1`:** shown only when `@prices` isn't empty; rows sorted by
   ticker so they don't jump; each `<tr>` has `id="price-TICKER"` so LiveView patches one row
   in place; price formatted to 2 decimals, time as `HH:MM:SS` UTC (`Calendar.strftime` works
   for `DateTime` and `NaiveDateTime`). Replaced the TODO comments with short "why" comments.
3. **TODO 5, tests:** mount with a DB row now asserts the row renders (`has_element?` on
   `#price-ZZTEST`); a broadcast test checks a new ticker adds a row and a second broadcast
   updates it in place. Unique `ZZ*` tickers because `"stocks:live"` is global and tests run
   async. `render(view)` is a call queued behind the broadcast (same sender), so no sleeps.
4. Checks: `mix format`, `mix compile --warnings-as-errors`, `mix test` 3 runs, **65 tests, 0
   failures**. Real server: `/prices` 200, no errors in the log.
5. **Correction after I opened the page:** it stayed on "Waiting for prices…". The agent had
   assumed `Mock.Streamer` broadcasts on `"stocks:live"`; it broadcasts on `"stocks:mock"`
   (`mock/streamer.ex:9`), and the React app picks a topic by joining `"stocks:mock"` or
   `"stocks:live"`. Fix: `/prices?source=mock` subscribes to `"stocks:mock"` (starts empty,
   first tick within 1.5 s; Mock never saves to the DB), `/prices` stays on `"stocks:live"`
   (real Finnhub ticks, market hours only). The page shows which source it's on. New test: a
   mock-source page gets `"stocks:mock"` broadcasts and ignores `"stocks:live"`. 66 tests pass.
   Lessons: check the producer's topic in code instead of assuming; and both UIs can run the
   metrics on the same mock stream any day, not only during market hours.

### Trading module draft (step C, agent-written, uncommitted until I review it)
- `StockFetcher.Trading` + `portfolios`/`positions`/`orders` tables (integer cents), 18 tests.
  Market orders, one shared demo portfolio, $100,000 starting cash (assumptions until John
  answers Q1 and Q3). `mix.exs` gets the standard `test` alias so the test DB is migrated.
- Design points I must explain back after reading `trading.ex`: (1) why a conditional
  `UPDATE ... WHERE cash_cents >= total` instead of read-check-write; (2) why the caller passes
  the price instead of the module looking it up (step D).
- Not verified: no concurrency test (the SQL sandbox makes one awkward).

### LiveView vs. React observations
- `PricesLive` is about 80 lines including the template and has no client code beyond the
  shared `app.js`. The React equivalent needs a fetch for the initial list, a channel join, and
  client state; the comparison metric will measure it properly.
- The same shape mismatch (`inserted_at` vs `timestamp`) would exist in React; there it would
  surface in the browser as `undefined`, here as a server-side `KeyError` in the LiveView process.

### Next (Nov 2 onward)
- Review `trading.ex`, write the two explanations above, commit step C.
- Step D notes, LiveView trading panel (E), React panel (F), limit + stop (G-lite).
- Before the first deploy: Dockerfile asset step, ship with security fix `1b23b90`.
- Send John follow-up questions 7–12 (Q9 decides whether B2/Alpaca stays in scope).
- Proposed cuts (record in `PLAN.md` once agreed): dividends (H), 4-hour chart (I), staging,
  risk preview, Short/Cover, take-profit.

## 2026-11-04 — Reviewing the trading draft (step C), explain-back

### Question 1: why one conditional `UPDATE` instead of read, check, then write
My answer:
> With read-then-write, two requests can both read the cash before either one writes, so both
> pass the check and one debit is lost (a lost update). The conditional
> `UPDATE ... WHERE cash_cents >= total` does the check and the write in one atomic step, so the
> second request checks against the cash left after the first, and is rejected if that isn't
> enough.

How I got there: $1,000 cash, two $800 buys at the same moment (two tabs, a double-click, or
the LiveView and React panels on the same demo portfolio). Read-then-write: both read $1,000,
both pass, both write `1000 - 800`, so cash ends at $200 after $1,600 of buys. I first said only
one order goes through; the timeline showed both do. With one request the two versions are
identical; the choice only matters under concurrency.

Terms I had mixed up:
- *Atomic* (can't be split, nothing runs between the check and the write) vs *in sequence*
  (read-then-write is also sequential; the problem is the gap).
- *Serialized* (the DB runs the two `UPDATE`s one after another) vs *synchronous* (the caller
  waits). Only this critical section is serialized; the rest of each request still overlaps.
- The second request isn't always rejected: it re-checks against the remaining cash.

### Things I learned reading `trading.ex` and its test
- There's no SQL text in `buy/5`: Ecto generates it. `from(p in Portfolio, where: ...) |>
  Repo.update_all(inc: [cash_cents: -total])` becomes
  `UPDATE "portfolios" SET "cash_cents" = "cash_cents" + ? WHERE id = ? AND cash_cents >= ?`
  (printed with `Ecto.Adapters.SQL.to_sql/3`). `^` values are sent as parameters, not pasted
  into the SQL.
- `{debited, _}` is the number of rows changed (0 or 1), not money. It can't exceed 1 because the
  `WHERE` matches the primary key; `sell/5`'s `reduced` relies on the unique index on
  `(portfolio_id, ticker)` the same way. `update_all` on a non-unique column would change every
  matching row.
- `:ok = Sandbox.checkout(Repo)` raises a `MatchError` if checkout fails. A crash in `setup`
  fails that one test (reported as failed, not skipped); `setup` runs again for each test, so a
  shared cause fails all of them one by one. A crash in `setup_all` fails the whole file. The
  stacktrace's `__ex_unit_setup_0/1` frame shows the crash was in setup, not the test body.

### Question 2: why the caller passes the price instead of `Trading` fetching it
`Trading` needs a price for the total, the position's average cost, and the order record; the
question is only who supplies it. My answer:
> The caller passes the price so the price charged is the price the UI showed when John clicked.
> If `Trading` looked it up itself, a new tick could arrive in between and he'd be charged a
> different price. It also lets the mock page trade (mock prices are never saved to the DB) and
> lets tests pass an exact price.

Caveat for step F: this is safe for the LiveView because `@prices` lives in the server-side
LiveView process. The React endpoint must not take the price from the request body (anyone could
send `price: 0.01`); it takes ticker, side and quantity, and the server supplies the price
(step D decides from where). `Trading` doesn't change either way.

### Step C committed
Reviewed `trading.ex`, the schemas, migration and tests; both explanations above. Still no
concurrency test (the SQL sandbox makes one awkward); question 1's reasoning covers it for now.

### John's update: scope is final
John replied that everything on the current to-do list is good enough and there's no need to
expand scope further. Recorded in `PLAN.md` §4 "Agreed scope" and the §8 schedule: build both
trading panels, limit entries with stop-losses, and trade history; cut dividends, 4-hour candles,
staging, Short/Cover, take-profit, the risk preview, and the Alpaca poller (5 Finnhub tickers plus
the mock stream). I'll confirm at the handover that the Finnhub tickers are enough to practise on
in place of QBTS.

### Step D: where the price comes from
My answer:
1. The LiveView's Buy handler (`handle_event`) takes the price from `socket.assigns.prices`,
   the same data `render/1` shows as `@prices`, kept current by `handle_info`.
2. If the ticker has no price, it passes `nil`; `to_cents(nil)` returns
   `{:error, :unknown_ticker}` and the LiveView shows `Trading.error_message(:unknown_ticker)`
   ("Unknown ticker: no price available."). No cash moves and no order is written.
3. Source of truth: the server decides the price, never the client, or a client could send its
   own price. React sends ticker, side and quantity only.

Things I mixed up on the way: the layout holds no data (it's the HTML wrapper); the DB is only
read once, in `mount/3`; `@name` is a module attribute in normal code but `assigns.name` inside a
`~H` (HEEx) template, so callbacks must write `socket.assigns.prices`.

Resting limit/stop orders (step G) will need their own supervised process watching the price
stream, outside any LiveView; designed on Friday.

### Step E: LiveView trading panel (agent-written except the `handle_event` case)
- On `PricesLive`, under the prices table: a form with a ticker dropdown (tickers in `@prices`),
  quantity, and Buy/Sell buttons (the clicked button arrives as `"side"`); cash; positions with
  average cost, live price and unrealized P/L; order history. Works on `?source=mock` too.
- Dropdown chosen over a text field (fewer typos). "Unknown ticker" is still tested by sending
  the event directly. The React panel must use a dropdown too, to match.
- `handle_event` reads the price from `socket.assigns.prices` (step D) and calls `Trading`. The
  `case` on the result is mine to write (TODO in the code); 5 panel tests fail until it's done.
- Bonus idea recorded in `PLAN.md` §4: a hidden `claude -p` console for plain-text orders.
- Light/dark toggle (agent-written): a plain JS button in the root layout plus an inline
  `<head>` script that applies the saved theme before first paint; Tailwind's `dark:` variant
  keys off `<html data-theme="dark">`. LiveView vs React note: a client-only preference stays
  in client JS. Sending it through a LiveView event would add a server round trip for nothing.

### Flaky tests: "Database busy" (and question 1 again)
- After the panel, about 1 run in 4 failed with `Exqlite.Error: Database busy`, in tests I
  hadn't touched. Cause: SQLite has one write lock, each test's sandbox transaction holds it
  until the test ends, and now every `PricesLive` test writes (the demo portfolio on mount), so
  async writers queued past the 2 s busy timeout.
- Tried: a longer busy timeout (still flaky), and making `demo_portfolio/0` read before
  inserting (much worse: a transaction that has already read can't wait for the write lock, so
  SQLite fails it immediately). That is the same read-then-write problem as question 1, and why
  `buy/5` writes first. Reverted both.
- Fix: the four modules that write to the DB run `async: false` (the approach the
  `ecto_sqlite3` docs suggest). 10 runs in a row, 0 failures; the suite still takes 0.4 s.

### Next
- Write the `handle_event` case; the panel tests go green.
- Dockerfile asset step and first deploy; React panel (F).
- Book the Saturday Nov 7 handover with John.

## 2026-11-06 — `handle_event` case done (step E committed)

### The `case` (mine), and the mistakes on the way
- Attempt 1: assigned `orders: order` (one struct where the template loops over a list →
  `Protocol.UndefinedError: Enumerable`) and had no `{:error, _}` branch (→ `CaseClauseError`).
- Attempt 2: called `error_message/1` without `Trading.`, and the error branch set
  `portfolio: nil` / `orders: nil`, wiping what the page showed. On an error nothing but the
  message should change.
- Attempt 3: both branches right, but a leftover `{:noreply, socket}` after the `case`. A function
  returns its last expression, so the `case` result was thrown away and the old socket returned.
  Deleting it: 72 tests, 0 failures, 5 runs in a row.

### Things I learned
- `assign(socket, ...)` takes the socket first and returns a new one (data is immutable), which
  is also why it pipes: `socket |> assign(...) |> assign(...)`. Keys not mentioned are kept.
- A callback is a function I write but the framework calls (`mount`, `render`, `handle_event`,
  `handle_info`). I never call `handle_event` myself; the LiveView process does when the form
  is submitted. Same idea as `onClick={handleBuy}` in React or the function given to `Enum.map`.
- `@impl true` ≈ Java's `@Override` / C++'s `override`: a compile-time check that the function
  is a callback of the behaviour (`use Phoenix.LiveView` adds `@behaviour`), so a typo like
  `handle_evnet` warns instead of silently never being called. A behaviour is like an interface,
  but without objects or inheritance: state comes in as an argument (`socket`) and goes back out.

### LiveView vs. React observations
- My first impression was "beauty in simplicity" thanks to metaprogramming. More precisely:
  Elixir's simplicity comes from pattern matching, immutable data and processes (`trading.ex`
  is plain functions plus Ecto's query macros). Phoenix adds macros on top (`use`, `~H`, Ecto's
  `from`) so the framework's complexity stays out of my code. The price: the code looks like
  one thing and compiles to another. `@prices` means `assigns.prices` inside `~H` but a module
  attribute elsewhere, and errors can point into generated functions (`__ex_unit_setup_0/1`).
  React has the same trade-off with JSX, which compiles to function calls.

### Dockerfile asset step and first deploy of the branch (`e11824a`)
- The build stage copied only `config`, `lib`, `priv`, so a release would ship with no CSS/JS:
  unstyled page, and no `app.js` means no WebSocket, so the buttons would do nothing. Added
  `COPY assets assets` after `lib` (Tailwind scans `lib/stock_fetcher_web` for class names via
  `@source`) and `RUN mix assets.deploy` before `mix release` (the release copies `priv/static`
  when it runs). Agent-written at my request; I found where the copies happen.
- First local `docker build` died with exit 137 (out of memory) at `mix local.hex`, before our
  lines: containers here allow ~1 billion open files and the Erlang VM sizes a table from that.
  Local builds need `docker build --ulimit nofile=65536:65536 .`; `fly deploy` builds remotely.
- `fly deploy` (with security fix `1b23b90`): migrations created the trading tables on the
  existing volume. Checked in production: `/api/health` and `/api/stocks` 200, React channel
  socket from `tinle-ri.github.io` 101, `/prices` 200 with the panel, assets served, `/live`
  socket 101 from its own origin and 403 from a foreign one. No test order placed: it would
  show up in the demo portfolio John uses at the handover.
- Metric for later: LiveView first load transfers JS 56.7 KB and CSS 3.7 KB (brotli-compressed
  on the way out, though `Plug.Static` has `gzip: false`).

### LiveView vs. React observations (deploy)
- No domain needed: Fly gives every app `<app>.fly.dev` with HTTPS. The LiveView page lives on
  the same app as the API, because the server renders it. React is static files on GitHub
  Pages calling the Fly backend: two hosts, so the backend needs CORS/`check_origin` entries for
  the Pages origin. LiveView's socket only accepts its own origin.
- LiveView wins: one deploy, nothing to configure between frontend and backend, and a backend
  change ships together with its UI, so they can't drift.
- React wins: GitHub Pages serves from a CDN even if Fly is down, so the SPA can still load and
  show "can't reach server"; if the one Fly machine is down, `/prices` doesn't load at all. And
  every LiveView interaction goes to the single machine in `sjc`, which a far-away user feels
  on each click (should show up in the throttled click-to-confirmation metric).

### Step F: React trading panel (backend `798bf3b`, React `b33c05c`), live
**Design.** REST (`GET /api/portfolio`, `POST /api/orders {ticker, side, quantity}`) over a
channel message: `api.js` already uses `fetch`, `/api` already has CORS and rate-limit plugs,
errors map to HTTP status, and the bonus `claude -p` console can curl it. The one point for a
channel: it reuses the open WebSocket, closer to LiveView, so REST adds a request per order to
React's click latency. Record that with the metric instead of hiding it.

**Where the price comes from (my explain-back).** I guessed telemetry; it's one step later.
`save_price/2` inserts the row first, and only on `{:ok, _}` fires the telemetry event that
leads to the `"stocks:live"` broadcast. React's prices come from `GET /api/stocks` (that table)
plus those broadcasts, so the newest saved row is the newest price React can have shown:
`StockFetcher.latest_price/1`. LiveView charges what its own process rendered
(`socket.assigns.prices`); React's server can't know what the browser displayed, so it uses the
source both were filled from. Neither trusts a client price (a test sends `price: 0.01`; it's
ignored). Edge cases: a tick between reading and clicking fills at the newer price (same in
LiveView); mock prices are never saved, so they can't be traded over the API.

**Backend (agent-written except the error branch).** `TradingController`; `confirmation/1` and
`format_cents/1` moved into `Trading` so both panels show identical text; 60/min rate limit;
11 tests. Gotcha: a JSON POST from another origin sends an `OPTIONS` preflight first, and router
pipelines (so `CORSPlug`) only run on a matched route, so it needed an `options "/orders"`
route. The existing GETs never hit this because simple GETs skip the preflight.

**My part: the `{:error, reason}` → 422 branch.**
- `send_resp` sends a raw string; `json/2` encodes the map, sets the content type, then calls
  `send_resp` itself. `put_status` only records the status on `conn`.
- First try: `put_status(reason)` → `FunctionClauseError in Plug.Conn.Status.code/1`. It turns
  status atoms into numbers with one clause per known name; `:insufficient_cash` isn't one. The
  reason goes in the body, the status is 422 for all of them.
- 422's atom is `:unprocessable_content` in Plug 1.20 (`:unprocessable_entity` is the pre-2022
  name, still accepted). 83 tests, 0 failures.

**React (agent-written, including `submitOrder` at my request).** `fetchPortfolio()`,
`placeOrder()` (never throws: resolves `{ok, body}`, so the UI has the same two branches as
`handle_event`), and `TradingPanel.jsx` mirroring the LiveView panel (same ids, dropdown,
P/L from the existing price stream, order history). Checked with curl against the local backend
(CORS from `localhost:5173`, buy, oversell) using a temporary price row, then cleaned up.

**Deploys.** Backend to Fly (additive, no migrations), then the React build to GitHub Pages
with `npx gh-pages -d dist --dotfiles` from `feat/trading-panel`, which isn't merged yet: still
needs a PR to `main`. Order mattered: the SPA would have shown "Couldn't load the portfolio"
without the backend endpoints. Tried it in the browser on the live SPA: it works.

**Metrics so far (record predictions before the rest).** Production JS: React 359 KB
(121 KB gzipped) vs LiveView 145 KB (44 KB gzipped; 56.7 KB brotli on the wire).

### LiveView vs. React observations (step F)
- Same feature, same backend rules, different frontends. My `handle_event` case and React's
  `submitOrder` make the same decision: on success replace the portfolio and confirm, on error
  change only the message. LiveView: `assign` returns a new socket, the server re-renders and
  sends a diff. React: `setPortfolio` schedules a re-render in the browser from the JSON.
- React needed things LiveView didn't: a JSON shape for every struct (built field by field so
  nothing internal leaks), CORS plus a preflight route, an API module, and loading/error states
  for the portfolio fetch. LiveView got the portfolio in `mount/3` with no API at all.
- Order times are UTC in both panels (the LiveView server doesn't know the browser's timezone;
  React matches it), while React's watchlist shows local time. Ask John if that matters.

### Problem I found: after-hours orders filled at a stale price
- Finnhub doesn't give after-hours prices, and after the close the Worker stops polling
  altogether, so an order at 8 PM filled at the last price before 4:00 PM ET. Real brokers
  reject or queue market orders when the market is closed (extended hours need limit orders
  and a feed that covers them).
- Options: (A) reject when closed, (B) queue to fill at the open (really a pending order, so
  it fits step G), (C) after-hours prices from Alpaca IEX (the cut B2 poller; thin volume).
  Chose A now; B can come with G.
- My design answers: the check lives in `Trading` (one source of truth for both UIs), with
  `now` injected for tests; mock orders are exempt (simulated prices, and the mock demo is
  most useful after hours).
- Built: `place_market_order/6` takes `source:` (`:live` default, `:mock`) and `now:`; new
  error `:market_closed` ("Market is closed. Orders fill Mon-Fri, 9:30 AM-4:00 PM ET.");
  `PricesLive` passes its source, the API is always live. A request or LiveView event can't
  carry `now:`, so `config/test.exs` pins the test clock to a Wednesday 11:00 AM ET
  (`:trading_fixed_now`, unset in dev/prod) and the closed-market tests override it. 6 tests.
- Mine: `check_market_hours/2`, two clauses (`:mock` → `:ok`; `:live` → `:ok` or
  `{:error, :market_closed}` from `MarketHours.market_open?(now)`). Learned: read the clock once
  at the edge and pass the time down; inside the check, use the `now` argument, never
  `DateTime.utc_now()`, or tests depend on when they run. `_now` marks an argument as
  deliberately unused. An unknown source crashes with `FunctionClauseError`, which is what I
  want for a bug in my own code. 89 tests, 0 failures.
- Known limitation: `MarketHours` doesn't know holidays (it says "open" on Thanksgiving).
- Ask John at the handover: is rejecting after-hours orders what he expects, or does he trade
  extended hours and want queued orders (B)?

### Step G: limit entries with a hard stop-loss (LiveView only)
**Scope.** Long trades only: a limit buy entry, plus the stop-loss sell it creates when it
fills, and cancel. Of the four exits (long/short × stop-loss/take-profit) only the long
stop-loss exists. Take-profit (with OCO) and shorts were deprioritized for this deadline with
John's agreement (Nov 4), not because they're infeasible: take-profit is about half a day,
shorts one to two days (negative positions, P/L sign, the collateral rule in open question 8).

**Paper trading has no counterparty.** My question: with nobody on the other side, are fills
realistic? No: Capstock ignores the bid-ask spread, price impact, the queue at a price, and
partial fills, so it's optimistic. The queue matters most for limits: a touch at your limit
may not fill in a real market. Fill rules, decided by me with John's permission, strict so paper
results never flatter him:
- Limit buy: only when a price trades *through* the limit (strictly below), filled at the limit.
- Stop sell: at or below the stop, filled at that tick's price, so a gap gives a worse fill.
- A limit already above the current price fills immediately at the current price (if the
  market is open), like a real exchange.
Spread, impact and partial fills stay ignored and are written down: small for John's sizes in
liquid stocks, and we have no bid/ask data.

**Process design (my answers).**
1. A supervised GenServer subscribed to the price topic; not `PricesLive`, because a LiveView
   dies with its tab and a stop-loss has to work while John isn't looking.
2. Open orders live in SQLite. A GenServer's state is just memory and is gone when it crashes.
3. Cancel vs fill: each is one conditional `UPDATE ... WHERE status = 'open'`; whichever runs
   first flips the status, the other matches 0 rows (fill rolls back before money moves; cancel
   says "no longer open"). A lock alone isn't enough: the second writer would wait and then
   overwrite. The condition re-checks the state. (Alternative: route cancels through the
   GenServer's mailbox. Kept the DB guard: works while the watcher restarts, rule stays in
   `Trading`.)
4. Saturday's demo with the market closed: the mock stream.

**Agent refinements, agreed.**
- The watcher keeps *no* copy of the orders: on each tick it queries the open orders for that
  ticker (indexed; live 5 per 15 s, mock 1 per 1.5 s). Nothing to reload after a crash, no
  messages for new or cancelled orders, no copy that can disagree with the DB.
- One `OrderWatcher` per source (`:live` on "stocks:live", `:mock` on "stocks:mock"). Mock uses
  the same tickers with made-up prices; separate watchers mean a mock tick can't reach a live
  order.
- A separate mock portfolio ("demo-mock"). Found while designing: since step E, mock market
  orders had been mixed into the real-price portfolio.

**Built.** `pending_orders` table (`source`, `type`, `trigger_cents`, `stop_cents`, `status`
open → filled/cancelled/rejected, `parent_id`, `order_id`); `Trading.place_limit_order`,
`fill_pending_order` (claim, fill through the market-order code, create the stop, all in one
transaction; rejected if it can't be afforded), `cancel_pending_order`; `OrderWatcher`, off in
tests (each test starts its own on a private topic against the SQL sandbox); in `PricesLive` a
separate "Limit buy with stop-loss" form (the benchmark form is unchanged, for fairness with
React), Open orders with Cancel, and fills pushed to the page over PubSub. 23 new tests incl. a
killed watcher being restarted by its supervisor and still filling.

**Mine: `fill_rule/2` and `OrderWatcher.handle_info/2`.**
- `fill_rule`: first try had one-argument heads, so the price was undefined and the compiler
  saw a separate `fill_rule/1`. Then the old catch-all stub was still the first clause:
  clauses are tried top to bottom, so specific clauses go first and the catch-all last; a
  failing guard counts as "doesn't match". Named the tick argument `price_cents`: dollars
  (floats) and cents (integers) both exist here, and the unit in the name makes a ×100 mistake
  visible.
- `handle_info`: `Enum.each(orders, fn order -> case ... end end)`. First try put
  `{:noreply, state}` inside the `:wait` branch, so the function returned `Enum.each`'s `:ok`
  and the GenServer crashed on every tick with `bad return value: :ok` (a crash loop the
  supervisor would eventually give up on). Inside the `fn`: the result for one order,
  discarded; last line of `handle_info`: the result the GenServer checks.
- Learned: stop-loss vs take-profit. Both close a position; stop is below a long entry and is a
  stop order (guarantees the exit, not the price), take-profit is above and is a limit order
  (guarantees the price, not the exit). Set together they're a bracket, linked as OCO.

**Bug I found trying it: forms reset on every tick.** Dropdowns closed and typed numbers went
back to the defaults. Each tick changed `@prices`, which re-sent the dropdown options; and
LiveView only protects the *focused* input from re-renders, so the others were reset to what the
server last rendered. Fix: `phx-change` keeps the form's values on the server (`@order_form`,
`@limit_form`, debounced 250 ms), and the options come from a separate `@tickers` assign that
only changes when a new ticker appears. Regression test added.

### LiveView vs. React observations (step G)
- The form bug is a LiveView-specific cost. React's panel never had it: controlled inputs keep
  their state in the browser, so re-rendering the table can't touch them. In LiveView the server
  renders the form, so it must be told what's in it: a WebSocket message per edit. Count those
  next to "bytes per price tick" in the metrics.
- The resting-order watcher is plain OTP and would serve a React UI unchanged; only the page
  updates (a PubSub event straight into the LiveView process) are LiveView-specific. React
  would need a channel event or polling for "your order filled".

### Trying it on the mock stream
- Limit at $169.20 with AAPL at $168.98, stop $168.80: filled immediately at $168.98, and the
  stop sold 8 s later at $168.35, $0.45 past the stop (a gap), for −$6.30 where I'd planned
  −$1.80. Stopped out by noise: the stop was $0.18 away and mock ticks move up to $0.75. Same
  reason John puts stops past the swing, not next to the entry.
- A winning trade (10 AAPL at $164.41, up to +$38.90) showed the gap that matters most: I
  couldn't move the stop up to break-even or to lock in profit. A stop only exists when an entry
  creates it, and cancelling it leaves no protection.
- Next features, ranked from using it: (1) move/trail the stop on an open position, (2)
  take-profit with OCO, (3) shorts. Ask John which he misses most.

### Next
- Deploy step G (runs the `pending_orders` migration on Fly, starts both watchers).
- Open the PR `feat/trading-panel` → `main` in `CapStock_FrontEnd`.
- Handover with John on Sat Nov 7: walk through limit + stop on `/prices?source=mock`; ask about
  after-hours rejection, UTC times, touch fills, and which next feature; decide whether to reset
  the live demo portfolio first.
- Metrics (predictions first), then the final log, merge and submission on Sunday.

## 2026-11-07 — John's handover reply: accepted, decisions delegated to me

John tried it and replied that it **meets all his needs**. For anything further (UI or
features) he wants me to take the initiative and make the decisions myself. So the open
questions from the handover are now mine to settle, and each answer has to rest on what he said
in the interview, not on what I'd find fun to build.

### Decisions
1. **Live orders after hours: keep rejecting them.** Finnhub doesn't update outside market hours,
   so a fill would use a stale price. An honest "market closed" beats a fake fill.
2. **Times: show the viewer's local time instead of UTC.** The React SPA already does this
   (`toLocaleTimeString()` uses the browser's zone, which follows the viewer automatically).
   LiveView renders on the server, which doesn't know the viewer's zone: it has to be sent
   (connect params or a JS hook). A small place where LiveView loses.
3. **Touch fills: stay off.** A limit needs the price to trade through it. A simulator that fills
   more easily than a real market teaches false confidence.
4. **Next features: all four exit scenarios**: long take-profit / stop-loss and short
   take-profit / stop-loss, starting with moving the stop (the gap my own winning trade
   showed).

### Order of work (metrics before features)
Measure the metrics *before* adding LiveView-only features. Today the trading panel is identical
in both UIs; every feature added to `/prices` afterwards grows its render and diffs and would
skew the comparison against LiveView.

### Working mode for the last two days
Short on time, I decided to write no code myself until the deadline: the agent writes it, and I
document *why* each piece exists and *what* it does in my Obsidian note (`Artifact 4.md`). This
overrides the CLAUDE.md "I attempt the last step" rule for Nov 7–8 only.

### Built: all four exit scenarios, moving exits, local times (agent-written)
- **The four scenarios are a 2×2 table:** direction (buying / selling) × type (limit / stop).
  `fill_rule/2` now has one clause per cell, matching on `side` as well as `type`:
  buying limit (long entry, short take-profit): price < limit, fills at the limit; selling limit
  (long take-profit, short entry): price > limit, at the limit; selling stop (long stop-loss):
  price ≤ stop, at the tick; buying stop (short stop-loss): price ≥ stop, at the tick.
- **Shorts:** two new sides, `"short"` and `"cover"`. A short position has a negative quantity
  and `avg_cost_cents` is the average entry, so the existing P/L formula
  `(price − avg) × quantity` is right with no special case (React's too). **Cash-secured:** the
  short's full value is set aside from cash, and the cover returns `qty × (2 × avg − price)`
  (collateral ± P/L). No leverage, so paper can't go bankrupt. Real brokers credit the proceeds
  and require margin (Reg T: 150%); trade-off recorded.
- **One meaning per side:** Buy on a short → `:short_open`; Short on a long → `:long_open`.
  Otherwise "Buy" would sometimes mean "cover" and the benchmark action would change meaning.
- **Benchmark untouched:** Short/Cover are a separate `#short-form` in LiveView, and the API
  rejects any side other than buy/sell, so the React panel and its spec are unchanged.
- **Brackets with OCO:** a limit entry takes a direction (long/short), an optional stop and an
  optional take-profit (`take_profit_cents`, new migration). Prices must be in order (long
  `stop < limit < TP`, short `TP < limit < stop`). When the entry fills, both exits are created;
  when one exit fills, the other is cancelled **in the same transaction** (conditional on
  "open", like cancel vs fill), so a position can't be closed twice.
- **Move an exit:** `Trading.amend_order/4`, a "Move" box next to each open stop/take-profit.
  It refuses a price that would fill immediately (`:would_fill_now`), checked by asking
  `fill_rule/2` "would this fill at the current price?" (no new rule to keep in sync). Moving
  a stop further away is allowed, like a real broker. Entries can't be moved (cancel instead).
- **Local times:** `<time phx-hook="LocalTime" datetime="…Z">`. The server renders UTC (it can't
  know the viewer's zone); a ~10-line JS hook rewrites it with `toLocaleTimeString`, and
  `updated()` re-applies it after LiveView patches the element. React's order history now
  uses the same call. NaiveDateTime gets a `Z` appended, or the browser would read it as local.
- **Known gap:** if an exit is moved in the same millisecond the watcher decides to fill it
  at the old price, the fill wins with the old price. SQLite serializes the two writes, so
  nothing double-fills; the window is one tick.
- Tests: 136 (was 112), all passing; `mix format` and `--warnings-as-errors` clean.

### LiveView vs. React observations (Nov 7)
- **Local time is where LiveView loses on a one-liner.** React formats in the browser, which
  knows the zone. LiveView renders on the server, which doesn't, so it needs a client hook, a
  `datetime` attribute and care with naive timestamps. Server rendering's cost: anything that
  depends on the *viewer's* machine has to be sent up or fixed up in JS.
- The production app (still `37fc3c3`) is unchanged, so the benchmark metrics can still be
  measured on it before these LiveView-only features are deployed.

### Metrics: my predictions (written before measuring)
Measured on production while it still runs `37fc3c3`, so the benchmark panel is the same in
both UIs and no Nov 7 feature is on the page yet.
1. **WebSocket bytes per price tick:** React less than LiveView, since LiveView has more
   logic. Ratio about **5 : 1** (LiveView : React).
2. **Bytes per keystroke (`phx-change`):** about **1 KB** (React sends nothing).
3. **Click Buy → confirmation:** about the **same** in both, a few bytes apart.
4. **Server memory per user:** about **3 KB** for both a LiveView process and a channel process.

### Metrics: results and the gap
How: a Node script (`ws`) opened a real LiveView session (`/live`, joined with the page's
session/static tokens) and a React-style channel (`/socket`, `stocks:mock`) side by side on the
**production** app (`37fc3c3`), for 45 s of mock ticks, twice. Orders were error-path only
(quantity 0) so no portfolio changed. Byte counts are WebSocket frame payloads (no compression
on either socket).

| Metric | LiveView | React | My prediction | Gap |
|---|---|---|---|---|
| Bytes per price tick | **151 B** avg (119 median) | **123 B** | LiveView 5× React | Only **1.2×**. LiveView sends just the changed values (price, time) keyed by position in the template; React's JSON repeats every key name. The average is above the median because some ticks also change a P/L cell or add a row. |
| Join / first payload | 4.4 KB join reply (5.7 KB HTML first) | 65 B join reply | – | LiveView's join carries the whole rendered page; React then makes separate API calls for history and the portfolio. |
| Bytes per input update (`phx-change`, debounced 250 ms, so one per pause in typing, not per key) | **113 B sent + 116 B reply** | 0 | ~1 KB | 4× smaller than I guessed, and fewer events than "per keystroke" implies. React really is 0: the input lives in the browser. |
| Click → reply (median, error path) | **46 ms** (118 B out, 99 B back) | **52 ms** (43 B body + HTTP headers, 88 B back) | about the same | Right: both are one round trip to Fly. LiveView is slightly faster because the WebSocket is already open and has no HTTP headers. |
| Successful order reply | a diff of the changed parts | **~1.8 KB** (the whole portfolio, grows with history) | – | React re-sends everything; LiveView sends what changed. Not measured on prod (no test orders in John's portfolio). |
| Server memory per user | **110–145 KB** per LiveView process | **27 KB** per channel process | ~3 KB both | Way off. The LiveView process keeps every assign (prices, portfolio, orders, open orders, form state) **plus** the rendered tree it diffs against. The channel process only holds its socket. ~4–5× per user. |

- Memory was measured on the **local dev server** (Nov 7 code, as a named node, processes found
  under `Phoenix.Socket.PoolSupervisor`), because a shell on production was blocked by the
  agent's auto-mode safety policy. Same code path; the dev mock portfolio has some order history.
- **Not measured:** throttled latency (needs DevTools "Slow 3G" in a browser) and browser
  CPU/memory. LiveView's first-load bundle was measured earlier: React 359 KB JS (121 KB gzipped)
  vs LiveView 145 KB (44 KB gzipped).
- **What I learned:** I expected LiveView to cost the network more and the server about the
  same. It's the opposite. On the wire LiveView is close to React per tick and cheaper per
  order. The real cost is **server memory**: every open tab holds a ~110 KB process with the
  page's state. At 1,000 users that's ~110 MB vs ~27 MB, fine for one Fly machine, but it's
  the number that grows with users, while React pushes that state into each user's browser.

### Wrap-up for the day: PLAN.md, merge, a wording fix
- **Wording fix:** the "bytes per keystroke" row is really bytes per *input update*. The text
  inputs use `phx-debounce="250"`, so LiveView sends one `phx-change` after each pause in
  typing, not one per key. Found while asking whether sending keystrokes is a security risk.
  Here it isn't (`wss://`, no secrets in the forms, typing never places an order, origin and
  signed-session checks), but the server does see what was typed before submit, even text
  later deleted. React keeps that in the browser. Worth deciding per form; never for
  password or card fields.
- **`PLAN.md` updated:** interview items marked built or cut, a "Scope update (2026-11-07)"
  section for what I added back after John delegated decisions (shorts, take-profit/OCO,
  movable exits, local times), metrics status, schedule actuals, the Bandit fix risk closed.
- **Merged `liveview` into `main`** with `--no-ff` after `mix format`, `mix compile
  --warnings-as-errors` and `mix test` passed. Done locally rather than through a GitHub PR
  (no `gh` CLI); the merge commit marks the Artifact 4 work. Production already runs this code,
  so no deploy was needed. The React PR (`feat/trading-panel` → `main`) is still to open in
  the GitHub web UI.
