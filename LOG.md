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
