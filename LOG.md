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
- **Interview 1 held and recorded** (transcript below).
- **User identity:** the interviewee asked to remain anonymous, so they are referred to by the
  pseudonym "John Daytrader" in the repo. Real name and contact details are not stored here.

### Interview 1 — transcript (John Daytrader)

> **Q:** "Most retail day traders lose money. How do you exploit institutional order flow and
> liquidity traps to build a consistent edge, and what specific rules govern your entries,
> stop-outs, and profit scaling?"
>
> **Trader:** "The reality is that 99% of day traders fail, so my entire edge comes down to
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
> **Q:** "Describe a high-stakes scenario where you put significant personal capital on the
> line. What was your analytical thesis, how did you handle risk versus emotion under pressure,
> and what was the outcome?"
>
> **Trader:** "A prime example was taking a $60,000 short position on QBTS.
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
- None yet.

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
