# LOG.md — Capstock LiveView (Artifact 4)

Dated record of what was planned, what changed, and why. Newest entries at the bottom. The
agreed plan lives in `PLAN.md`. *Condensed on 2026-11-08; the full day-by-day version is in git
history (commit `35e2df2`).*

---

## 2026-10-30 — Kickoff, plan, interview 1

- **Starting state:** no `PLAN.md`/`LOG.md`, `CLAUDE.md` uncommitted, no `liveview` branch, and
  a JSON-only app (no LiveView, esbuild or Tailwind). Permission received to work solo.
- **Wrote `PLAN.md`:** benchmark trading panel in both UIs, everything else LiveView-only;
  approach, metrics, schedule, risks. Added the persona statistics (97% lose / 3% profit / 1%
  consistently profitable, with sources and an accuracy note).
- **Interview 1** with "John Daytrader" (pseudonym; he asked to stay anonymous, so no real name
  or contact details are kept here). I interviewed, he answered.

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

### What interview 1 changed
- His workflow is **limit entries + hard stop-losses + 50% scale-out + shorts**, so those became
  LiveView-only features in priority order. The benchmark stays **market orders only**, small
  enough to build twice and compare fairly. "Sell" keeps its meaning; shorting would be a
  separate Short/Cover action.
- Resting orders need a **supervised process watching the price stream**, outside any LiveView
  (added to step D). Dividends weren't mentioned, so they moved down the cut list.
- Answers so far: order types answered; starting cash, accounts, dividends, "smooth" still open.
  His "99% fail" vs the 97/3/1 studies: both rough, noted.

### Second data source: Alpaca (market data only)
- Free paper key tested: one IEX latest-trades request covers many tickers (200 req/min);
  real-time SIP is 403, but historical SIP bars (incl. 4-hour, back to 2024) work. IEX volume on
  a QBTS bar was ~7% of SIP.
- **Decisions:** Alpaca for **data only**, never its trading API (fills and cash belong to my
  module); Finnhub Worker unchanged (React depends on it); one live source per ticker; polling,
  not Alpaca's WebSocket; a B2 poller for extra tickers and a step-I 4-hour chart (stretch).

---

## 2026-10-31 — Branch, step A (LiveView setup), security fix, first LiveView

- **Branch `liveview`** with the docs (`cb77166`). Renamed `stock_fetcher_Web` →
  `stock_fetcher_web` (`git mv`): generators write the lowercase path, and the two would
  collide on the case-insensitive Windows copy.
- **Deps** (`49aaffd`): LiveView 1.2.13, phoenix_html, esbuild, Tailwind **v4** (CSS config, a few
  hand-written components, no daisyUI).
- **Security fix** (`1b23b90`, lockfile only): `mix deps.get` showed advisories against versions
  already in production (Bandit: 15, mostly HIGH DoS; Mint: 6; plus decimal, plug_crypto).
  Lesson: my first check truncated the output and missed most of them. Shipped with the first
  LiveView deploy (accepted risk until then).
- **Plumbing** (agent-written, generator-style): asset aliases, esbuild/Tailwind profiles, `/live`
  socket, `:browser` pipeline, root layout, ~10-line `app.js`. `/api` and React's `/socket`
  untouched; 43 tests.
- **`PricesLive` TODO 1, mine** (`5f755f6`): subscribe only when connected. *Why:* `mount/3` runs
  twice; the first run is a one-shot HTTP render whose process can't push to the browser, so a
  subscription there is useless (and its mailbox fills). My first try put the `if` after the
  `{:ok, socket}` tuple, so mount returned `nil`: side effects first, return value last.
- **TODO 2 design, mine:** a new `latest_prices/0` (one `group_by` + `max(id)` query; works on
  weekends, unlike the 12-hour hydration function); load in both mounts so the first HTML has
  prices (LiveView's main edge); keep the broadcast shape `%{ticker, price, timestamp}`.
- **Editor gotcha:** ElixirLS kept a stale build after the version bump (`rm -rf
  .elixir_ls/build`).

**LiveView vs React:** React loads an empty shell, then fetches `/api/stocks`, then renders and
diffs in the browser. LiveView ships the data in the first HTML and diffs on the server, sending
only changed values. Cost: the data loads twice (once per mount), and on reconnect assigns are
gone, so money and orders must live in the DB, never only in a process.

---

## 2026-11-01 — Check-in, prices page done (step B), trading draft (step C)

- **Check-in:** portfolio card updated and linked to the `liveview` branch (the plan and log
  weren't on `main`); submitted on Canvas.
- **TODO 2, mine** (`04854e5`). Three bugs, all passed the tests: `select: s.id` instead of
  `max(s.id)` (SQLite allows it, Postgres wouldn't); treating `Repo.all`'s list as a map;
  `row.timestamp` on a struct that only has `inserted_at` (a `KeyError` hidden because the test
  DB was empty). **Lesson: green tests only cover the code they run.**
- **TODOs 3–5** (agent-written at my request): `handle_info` for ticks, the table, broadcast
  tests. When I opened the page it never got prices: the agent assumed the mock stream used
  `"stocks:live"`; it's `"stocks:mock"`. Fix: `/prices?source=mock`. Lesson: check the producer
  in code instead of assuming.
- **Trading module draft** (step C, agent-written): integer cents, one demo portfolio, 18 tests.

**LiveView vs React:** `PricesLive` is ~80 lines with no client code beyond `app.js`. The same
field-name mismatch would be a silent `undefined` in React and a loud `KeyError` here.

---

## 2026-11-04 — Reviewing step C, explain-backs, scope final, steps D–E

- **Why one conditional `UPDATE` (my answer):** read-then-write lets two requests both read
  $1,000 and both pass an $800 check (a lost update). `UPDATE ... WHERE cash_cents >= total`
  checks and writes in one atomic step, so the second sees what the first left.
- **Why the caller passes the price (my answer):** the price charged is the price John saw; a
  tick in between can't change it; mock prices (never saved) can trade; tests can pass exact
  prices. Caveat: the React endpoint must **never take a price from the client**.
- **John: the scope is final.** Built: both panels, limit entries with stop-losses, trade
  history. Cut: dividends, 4-hour candles, staging, Short/Cover, take-profit, risk preview,
  Alpaca poller.
- **Step D:** the LiveView fills at `socket.assigns.prices` (what the page shows); no price →
  `:unknown_ticker`. The server always decides the price.
- **Step E** (agent-written, my `handle_event` case pending): ticker dropdown, quantity,
  Buy/Sell, cash, positions with live P/L, history. Plus a light/dark toggle in plain JS (a
  client-only preference doesn't need a server round trip).
- **Flaky "Database busy" tests:** SQLite has one write lock, held by each test's sandbox
  transaction. Making the insert read-first made it *worse* (question 1's read-then-write again).
  Fix: `async: false` for modules that write.

---

## 2026-11-06 — Panel done, first deploy, React panel, after-hours rule, resting orders

- **My `handle_event` case** took three tries: a struct where a list was expected; an error
  branch that wiped the portfolio (on error only the message should change); and a leftover
  `{:noreply, socket}` after the `case`, which threw its result away. Learned: `assign` returns a
  new socket; callbacks are called by the framework; `@impl true` is like `@Override`.
- **Dockerfile asset step + first deploy** (`e11824a`, with the security fix): the release
  shipped no CSS/JS until `COPY assets` + `mix assets.deploy`. Local Docker needs `--ulimit
  nofile=65536:65536` (exit 137 otherwise). Checked in production; no test order in John's
  demo portfolio.
- **Step F, React panel** (backend `798bf3b`, React `b33c05c`): REST `GET /api/portfolio` and
  `POST /api/orders {ticker, side, quantity}`. The server prices it from the latest saved row (a
  test sends `price: 0.01` and it's ignored). A cross-origin JSON POST needs an `OPTIONS` route.
  **Mine:** the error branch (`put_status(reason)` crashed: the status is 422 for every reason,
  the reason goes in the body). Live on GitHub Pages from `feat/trading-panel` (PR still to open).
- **After-hours bug I found:** orders filled at the last pre-close price. Chose to **reject live
  orders when the market is closed** (`:market_closed`); mock is exempt. **Mine:**
  `check_market_hours/2`, with the clock injected (read it once at the edge, pass it down).
- **Step G, limit entries + hard stop-loss** (long only):
  - **Strict fill rules**, since paper has no counterparty: a limit fills only when the price
    trades *through* it; a stop fills at the tick price (worse on a gap).
  - **Design (my answers):** a supervised `OrderWatcher` per source, not the LiveView (a stop
    must work with the tab closed); orders live in SQLite; cancel vs fill is decided by
    conditional `UPDATE ... WHERE status = 'open'`. The watcher keeps no copy of the orders.
    Found: mock trades had been mixed into the real portfolio, so a separate "demo-mock" one.
  - **Mine:** `fill_rule/2` (one-argument heads at first; the catch-all first; named the
    argument `price_cents` so the unit is visible) and the watcher's `handle_info` (first
    returned `:ok`, which crash-looped the GenServer).
  - **Bug I found using it:** forms reset on every tick. Fix: `phx-change` keeps typed values
    on the server, plus a separate `@tickers` assign.
  - Mock trades showed a stop gapping past its price and, on a winner, that **I couldn't move
    the stop**. Ranked next: move the stop, take-profit with OCO, shorts.

**LiveView vs React:**
- **Hosting:** LiveView is one deploy with its API, no CORS. React is separate static files on
  a CDN, which can still load when the server is down.
- **The React panel needed more:** a JSON shape per struct, CORS plus a preflight route, an API
  module, and loading states.
- **The form-reset bug is a LiveView-only cost:** React's controlled inputs keep their state in
  the browser.
- **Bundle:** React 359 KB (121 KB gzipped) vs LiveView 145 KB (44 KB gzipped).

---

## 2026-11-07 — Handover accepted, decisions delegated, metrics, last features

**John tried it: "meets all my needs."** He handed further decisions to me; each one had to rest
on what he said in the interview.

- **Decisions:**
  1. Keep rejecting live orders after hours: an honest "closed" beats a stale fill.
  2. Show local time instead of UTC.
  3. No touch fills.
  4. Build all four exit scenarios (long/short × take-profit/stop-loss), starting with moving
     the stop.
- **Order of work:** metrics *before* new features, while both panels were still identical.
- **Working mode:** for Nov 7–8 the agent writes the code and I document the why and what in my
  Obsidian note (overrides the "I write the last step" rule for these two days).
- **Built:**
  - `fill_rule/2` as a 2×2 table (buying/selling × limit/stop).
  - **Shorts:** negative quantity, so the P/L formula is unchanged. Cash-secured: the short's
    full value is set aside, and the cover returns `qty × (2·avg − price)`. Buy on a short and
    Short on a long are refused.
  - **Brackets:** a limit entry with a stop and a take-profit; OCO cancels the other exit in the
    same transaction.
  - **Move an exit:** refused if it would fill at once (`fill_rule/2` reused).
  - **Local times** via a `LocalTime` hook.
  - The benchmark is untouched (separate short form; the API only takes buy/sell). 136 tests.
  - Known gap: a move and a fill in the same tick → the fill wins at the old price.

### Metrics: predictions (written first) and results

Measured on production (`37fc3c3`, panels still identical) with a Node script driving a real
LiveView session and a React-style channel on the same mock stream, 45 s, twice; orders
error-path only.

| Metric | Prediction | LiveView | React | Gap |
|---|---|---|---|---|
| Bytes per price tick | LiveView 5× React | **151 B** avg (119 median) | **123 B** | Only 1.2×: LiveView sends changed values; React's JSON repeats key names. |
| Join / first payload | – | 4.4 KB join (5.7 KB HTML) | 65 B join | LiveView's join carries the rendered page; React makes separate API calls. |
| Bytes per input update (debounced 250 ms, one per pause in typing) | ~1 KB | **113 B + 116 B reply** | 0 | Smaller than guessed; React really is 0 (state in the browser). |
| Click → reply (median) | about the same | **46 ms** | **52 ms** | Right: one round trip each; LiveView's socket is already open. |
| Successful order reply | – | a diff | **~1.8 KB** (whole portfolio, grows) | React re-sends everything. |
| Server memory per user | ~3 KB both | **110–145 KB** | **27 KB** | Way off: a LiveView process holds every assign plus the rendered tree. |

- Memory measured on the local server (same code): a production shell was blocked by the
  agent's safety policy. Not measured: throttled latency, browser CPU/memory.
- **Lesson:** I expected LiveView to cost the network more and the server the same. It's the
  opposite: close to React per tick, cheaper per order, and **~4–5× the server memory per tab**.
  That's the number that grows with users.
- **Typing and privacy** (from a question I asked): a `phx-change` sends form values *before*
  submit, even text later deleted. Harmless here (`wss://`, nothing secret, typing never
  trades), but decide per form, and never for passwords or card numbers.
- `PLAN.md` updated (scope update 1); `liveview` merged into `main`.

---

## 2026-11-07 (evening) — Round two, ahead of schedule

With the scope shipped and a day to spare, I added my own wish list, **LiveView only** (the
React SPA and the benchmark panel are unchanged).

**Decisions (asked and answered):**
- **"Are IEX prices real?"** Yes: IEX is a regular US exchange, and the free feed just covers its
  share of trades. Busy stocks are within about a cent, so: 50 liquid tickers, IEX for live
  prices, free 15-minute-delayed SIP history for candles. No Finnhub premium.
- **Portfolio storage: "tab-only + autosave."** A private session portfolio lives on the server
  only while the tab is open, the browser keeps the save, and Download/Import move it. No
  accounts, and nobody can touch anyone else's portfolio. Trade-off accepted: stops only fire
  while the tab is open.
- **Save file:** readable JSON, **signed** (HMAC from `secret_key_base`), so an edited file is
  refused and the record stays honest.
- **Sidebar by exit:** Long/Short × take-profit/stop-loss.

**Built** (177 tests by the end, each feature checked in a real browser with Playwright):
- **Data:** 50 tickers (`Tickers`); an Alpaca poller for 45 of them on a separate topic
  (`stocks:extra`, so React keeps its 5; not saved to the table React reads); a second mock
  streamer; `OrderWatcher` on both topics.
- **Chart:** a `Candles` cache per source (SIP 5-minute history plus live ticks; made-up mock
  history), drawn by a vendored Lightweight Charts in a hook behind `phx-update="ignore"`. One
  cache for every tab, so no per-user API calls.
- **Private portfolios:** `SessionJanitor` monitors each tab's process and deletes its portfolio
  on exit (a monitor always fires; `terminate/2` doesn't). Buying power $1k–$2M, account value
  and P/L since start. The save file includes open brackets' parents so OCO survives a restore.
  The autosave returns in the **connect params**, so mount restores before the first render.
  **Undo** instead of a confirm popup.
- **Sidebar:** the four exit strategies as an accordion with goal/how/why tutorials, "Example
  prices" and a **risk preview** ($ risk, % of account, target, R:R). A non-modal help panel.
- **Keyboard-first:**
  - the watchlist filter fuzzy-searches ticker and name, with **flash.nvim-style labels** (a
    letter that would continue the search is never a label);
  - `/` focuses the filter;
  - ticker dropdowns replaced by the watchlist selection, shown as a chip, and every button
    names its ticker;
  - fixed **jump keys** inside each number input (b, s, q, e, x, t, n; never `l`/`i`), and a/d/f/g
    on the closed exit panels;
  - **Enter never submits** (found: Enter in a quantity box would have pressed Buy).
- **Open orders:** grouped by bracket (by `parent_id`, exactly how OCO finds siblings) with a live
  price ladder. Click one to draw dotted lines on the chart (**blue take-profit, orange
  stop-loss**: green and red already mean up/down and buy/sell). History tags automatic fills
  (`orders.via`: take-profit, stop-loss, limit entry), kept in the save file.
- **Polish:** jump labels restyled as quiet keycaps like the filter's `[/]` (the bright pink was
  too loud in dark mode; pink stays for the flash labels, softened in dark mode);
  viewer's time-zone label (PST, CST…); equal input sizes; three portfolio panels;
  Apple-style scrollbars that pop in and **fade out** (a registered `@property` color, since
  scrollbars can't be transitioned).
- **Production log level → `:info`:** it was `:debug`, which logged every LiveView event's
  parameters. This corrected my earlier "nothing gets logged".

**LiveView vs React (round two):**
- **A process per tab made "private, no accounts" almost free** (one monitor). React would need
  a session token checked on every API call.
- **Connect params** hand the autosave to the server in the join, so there's no extra request.
- **The cost:** anything purely client-side must stay out of LiveView's way, because rows
  re-render on every tick and would wipe JS changes.
  - The flash filter rewrites one `<style>` element instead of touching the rows.
  - The scrollbar class goes through `liveSocket.js()`, which LiveView keeps across patches.
  - The chart sits behind `phx-update="ignore"`.
  - In React each of these is a `useState`.
- **Bundle:** 145 → 309 KB minified (44 → 97 KB gzipped), almost all chart library; React's is
  121 KB gzipped. Per-tick and memory metrics not re-measured.
- **Test lesson:** `assert_push_event` takes the first matching event in the mailbox, so stale
  events from earlier steps can pass a later assertion.

---

## 2026-11-08 — Deploy: an OOM, a fix, live

- Committed round two (`cc7d7df`), staged the Alpaca keys as Fly secrets straight from `.env`
  (never printed), deployed.
- **Production was down for about 3 minutes:** the 256 MB Fly machine **OOM-killed** the app ~2 s
  after boot (site 502). `Candles` held every decoded Alpaca page (~40,000 bars) at once: fine on
  my laptop, not on 256 MB.
- **Fix** (`2fcbf87`): process one page at a time, trimming as it goes (5,000 bars a page); start
  10 s after boot; garbage-collect after. ~19 MB peak locally. Release v26, no OOM since.
- **Verified on production:**
  - a private portfolio is created and a buy fills, so both new migrations ran;
  - autosave works;
  - 50/50 live tickers are priced, so the Alpaca keys work;
  - real candles show;
  - React's API still returns 200;
  - the test order was in a throwaway private portfolio.
- **Lesson:** tests can't catch an out-of-memory kill. Measure the memory of anything that loads
  data at boot, and know the server's size.
- Merged `liveview` into `main` (`abdb361`).
