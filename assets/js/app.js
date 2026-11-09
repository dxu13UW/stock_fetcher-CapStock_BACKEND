// Connects this page to its LiveView process over the /live WebSocket.
// The server sends HTML diffs and phoenix_live_view patches the DOM. The hooks below are the
// only places where the browser does more than render: local times, the chart, and the save file.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
// TradingView Lightweight Charts v4.2.3 (Apache-2.0), vendored so the Docker build needs no npm.
import {createChart, LineStyle} from "../vendor/lightweight-charts.mjs"
import {rank, assignLabels} from "./flash"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Which price source this page shows; each has its own save in localStorage.
const pageSource = () =>
  new URLSearchParams(window.location.search).get("source") === "mock" ? "mock" : "live"
const saveKey = (source) => `capstock-save-${source}`

// localStorage can throw (private mode, blocked storage), so every access is guarded and the
// app still works without it; only the autosave is lost.
const storage = {
  get(key) { try { return localStorage.getItem(key) } catch (_) { return null } },
  set(key, value) { try { localStorage.setItem(key, value) } catch (_) {} },
}

// The viewer's time zone, e.g. "PST" (short) / "Pacific Standard Time" (long). en-US gives the
// familiar US abbreviations (PST, MST, CST, EST, AKST, HST, and PDT etc. in summer); zones
// without one come out as "GMT+1". Computed for today's date, so daylight time is right.
const zoneName = (style) => {
  try {
    return new Intl.DateTimeFormat("en-US", {timeZoneName: style})
      .formatToParts(new Date())
      .find((part) => part.type === "timeZoneName")?.value
  } catch (_) {
    return null
  }
}

// Replaces the server's "UTC" label with the viewer's zone. updated() re-applies it if a
// LiveView patch ever resets the text.
const TimeZone = {
  mounted() { this.render() },
  updated() { this.render() },
  render() {
    this.el.textContent = zoneName("short") || "local time"
    this.el.title = zoneName("long") || ""
  }
}

// Times in the viewer's own zone. The server renders UTC (it doesn't know the browser's zone);
// this rewrites each <time phx-hook="LocalTime" datetime="..."> with the same
// toLocaleTimeString call the React panel uses. updated() runs after LiveView patches the
// element (e.g. a new tick reset the text to UTC).
const LocalTime = {
  mounted() { this.render() },
  updated() { this.render() },
  render() {
    const at = new Date(this.el.getAttribute("datetime"))
    if (!isNaN(at)) {
      this.el.textContent = at.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit", second: "2-digit"})
      this.el.title = zoneName("long") || ""
    }
  }
}

// Candlestick chart. The element has phx-update="ignore", so LiveView never touches what the
// library draws. The server sends the history once per selected ticker ("chart:data", from the
// StockFetcher.Candles cache) and then each tick of that ticker ("chart:tick"); the hook folds
// ticks into the last candle itself, the same rule as Candles.fold_tick/4 on the server.
// The library shows times as UTC, so each time is shifted by the browser's offset to read local.
const localTime = (unix) => unix - new Date(unix * 1000).getTimezoneOffset() * 60

const Chart = {
  mounted() {
    this.chart = createChart(this.el, {autoSize: true, ...this.theme()})
    this.chart.timeScale().applyOptions({timeVisible: true, secondsVisible: false})
    // Order lines (a clicked open order) are kept in view: the autoscale range is widened to
    // include their prices, so "focus" shows the candles and both exits together.
    this.lines = []
    this.linePrices = []
    this.autoscale = (original) => {
      const res = original()
      if (!res || this.linePrices.length === 0) return res
      return {
        ...res,
        priceRange: {
          minValue: Math.min(res.priceRange.minValue, ...this.linePrices),
          maxValue: Math.max(res.priceRange.maxValue, ...this.linePrices),
        },
      }
    }
    this.series = this.chart.addCandlestickSeries({
      upColor: "#059669", downColor: "#e11d48", borderVisible: false,
      wickUpColor: "#059669", wickDownColor: "#e11d48",
      autoscaleInfoProvider: this.autoscale,
    })
    this.last = null

    // Dotted lines for the focused open order (server sends [] to clear).
    this.handleEvent("chart:lines", ({lines}) => {
      this.lines.forEach((line) => this.series.removePriceLine(line))
      this.lines = lines.map(({price, color, title}) =>
        this.series.createPriceLine({price, color, title, lineWidth: 2, lineStyle: LineStyle.Dotted, axisLabelVisible: true})
      )
      this.linePrices = lines.map((l) => l.price)
      // Re-run autoscale with the new prices and bring the latest candles into view.
      this.series.applyOptions({autoscaleInfoProvider: this.autoscale})
      if (lines.length) this.chart.timeScale().scrollToRealTime()
    })

    // "Reset view" (JS.dispatch from the button): the same view the chart opens with. Panning or
    // zooming changes the time range, and dragging the price axis turns auto-scale off; this
    // undoes both. Order lines stay, and the autoscale provider keeps them in view.
    this.el.addEventListener("chart:reset", () => {
      this.chart.priceScale("right").applyOptions({autoScale: true})
      this.chart.timeScale().fitContent()
    })

    this.handleEvent("chart:data", ({interval, candles}) => {
      this.interval = interval
      const data = candles.map((c) => ({...c, time: localTime(c.time)}))
      this.series.setData(data)
      this.last = data.length ? {...data[data.length - 1]} : null
      this.chart.timeScale().fitContent()
    })

    this.handleEvent("chart:tick", ({price, time}) => {
      if (!this.interval) return
      const bucket = localTime(Math.floor(time / this.interval) * this.interval)
      if (this.last && bucket === this.last.time) {
        this.last = {...this.last, high: Math.max(this.last.high, price), low: Math.min(this.last.low, price), close: price}
      } else if (!this.last || bucket > this.last.time) {
        this.last = {time: bucket, open: price, high: price, low: price, close: price}
      } else {
        return // a late tick for an older candle
      }
      this.series.update(this.last)
    })

    // Follow the light/dark toggle (it changes <html data-theme>).
    this.observer = new MutationObserver(() => this.chart.applyOptions(this.theme()))
    this.observer.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
  },
  destroyed() {
    this.observer?.disconnect()
    this.chart?.remove()
  },
  theme() {
    const dark = document.documentElement.dataset.theme === "dark"
    return {
      layout: {background: {color: "transparent"}, textColor: dark ? "#a1a1aa" : "#52525b"},
      grid: {vertLines: {color: dark ? "#27272a" : "#f4f4f5"}, horzLines: {color: dark ? "#27272a" : "#f4f4f5"}},
    }
  },
}

// The save file. The server never keeps a user's portfolio after the tab closes, so the browser
// does: every change arrives as a "save" event (signed JSON from Trading.SaveFile) and is kept in
// localStorage. Download writes the latest save to a file; Import reads a file and sends its text
// to the server, which checks the signature and loads it. On the next connect, the save goes back
// in the connect params (see liveSocket below), so a reload resumes where it left off.
const MAX_SAVE_BYTES = 1_000_000

const SaveFile = {
  mounted() {
    const source = this.el.dataset.source
    this.latest = storage.get(saveKey(source))

    this.handleEvent("save", ({source, file}) => {
      this.latest = file
      storage.set(saveKey(source), file)
    })

    // Delegated, so the listeners survive LiveView re-rendering the buttons.
    this.el.addEventListener("click", (e) => {
      if (!e.target.closest("[data-action=download]") || !this.latest) return
      const day = new Date().toLocaleDateString("en-CA") // YYYY-MM-DD, local date
      const url = URL.createObjectURL(new Blob([this.latest], {type: "application/json"}))
      const a = Object.assign(document.createElement("a"), {href: url, download: `capstock-${source}-${day}.json`})
      a.click()
      URL.revokeObjectURL(url)
    })

    this.el.addEventListener("change", (e) => {
      const input = e.target.closest("[data-action=import]")
      if (!input || !input.files[0]) return
      const file = input.files[0]
      input.value = "" // so picking the same file again still fires "change"
      if (file.size > MAX_SAVE_BYTES) return this.pushEvent("import_save", {too_large: true})
      file.text().then((text) => this.pushEvent("import_save", {file: text}))
    })
  },
}

// Watchlist filter with flash.nvim-style jump labels. Runs entirely in the browser: no server
// round trip per keystroke, and the server never sees the search.
//
// LiveView re-renders the rows on every tick and would undo any attribute or class this hook
// put on them. So the hook never touches the rows: it rewrites one <style> element (inside its
// own phx-update="ignore" box) that hides non-matches, orders matches by score (the rows are
// flex items, so CSS `order` works) and puts each match's letter in its .flash-label via
// ::before. Patches can't undo a stylesheet.
//
// Keys: "/" anywhere focuses the filter. In the filter: a label letter selects that row, Enter
// the best match, Esc clears. Letters that continue the search are never labels (assignLabels).
const cssEscape = (id) => (window.CSS?.escape ? CSS.escape(id) : id)

const Flash = {
  mounted() {
    this.input = this.el.querySelector("[data-flash-input]")
    this.style = this.el.querySelector("[data-flash-style]")
    this.labels = new Map()
    this.matches = []

    this.input.addEventListener("input", () => this.filter())
    this.input.addEventListener("keydown", (e) => this.onKey(e))

    this.onSlash = (e) => {
      const t = e.target
      const typing = t.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(t.tagName)
      if (e.key === "/" && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) {
        e.preventDefault()
        this.input.focus()
        this.input.select()
      }
    }
    window.addEventListener("keydown", this.onSlash)
  },
  destroyed() {
    window.removeEventListener("keydown", this.onSlash)
  },

  // Read fresh each time: a new ticker can appear while the page is open.
  rows() {
    return [...document.querySelectorAll("#watchlist-rows [data-ticker]")].map((el) => ({
      ticker: el.dataset.ticker,
      name: el.dataset.name || "",
    }))
  },

  filter() {
    const query = this.input.value.trim()
    if (!query) {
      this.labels = new Map()
      this.matches = []
      this.style.textContent = ""
      return
    }
    const rows = this.rows()
    this.matches = rank(query, rows)
    this.labels = assignLabels(query, this.matches, rows)

    const rules = ["#watchlist-rows > [data-ticker] { display: none; }"]
    this.matches.forEach((row, i) => {
      // "#watchlist-rows > #price-X" outranks the hide-all rule above (two ids beat one id plus
      // an attribute); plain "#price-X" would lose and stay hidden.
      const id = `#watchlist-rows > #price-${cssEscape(row.ticker)}`
      rules.push(`${id} { display: grid; order: ${i}; }`)
      const key = this.labels.get(row.ticker)
      if (key) rules.push(`${id} .flash-label { display: inline-flex; } ${id} .flash-label::before { content: "${key}"; }`)
    })
    if (this.matches.length === 0) rules.push("#watchlist-empty { display: block; }")
    const summary = this.matches.length === 0
      ? "no matches"
      : `${this.matches.length} match${this.matches.length === 1 ? "" : "es"} · press a letter to jump`
    rules.push(`#watchlist-count { font-size: 0; } #watchlist-count::after { content: "${summary}"; font-size: 0.75rem; }`)
    this.style.textContent = rules.join("\n")
  },

  // A key this handler acts on is "claimed": preventDefault + stopImmediatePropagation, so the
  // page-wide jump-key listener never sees it. Without that, a label like "s" would jump to its
  // row, blur the filter, and then the same key press would reach the jump-key listener, which
  // (no longer "typing") focused the Short quantity box (bug found 2026-11-08).
  onKey(e) {
    const claim = () => { e.preventDefault(); e.stopImmediatePropagation() }
    if (e.key === "Escape") {
      claim()
      this.clear()
      this.input.blur()
      return
    }
    if (e.key === "Enter") {
      claim()
      if (this.matches[0]) this.jump(this.matches[0].ticker)
      return
    }
    // A single lower-case letter that is a label: jump instead of typing it.
    if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
      const ticker = [...this.labels].find(([, key]) => key === e.key)?.[0]
      if (ticker) {
        claim()
        this.jump(ticker)
      }
    }
  },

  jump(ticker) {
    this.pushEvent("select_ticker", {ticker})
    this.clear()
    this.input.blur()
    // After the filter is gone the row is back in alphabetical order; bring it into view.
    requestAnimationFrame(() => document.getElementById(`price-${ticker}`)?.scrollIntoView({block: "nearest"}))
  },

  clear() {
    this.input.value = ""
    this.filter()
  },
}

// Jump keys for number inputs, the flash idea applied to forms. When you're not typing, each
// number input shows its letter (rendered by the server as .jump-label + data-jump); pressing
// it focuses that input and selects its value. Esc inside any field leaves it. The only buttons
// with a key are the exit-panel headers (opening a panel never trades). Enter never submits a
// form: placing an order always takes a click.
// The only state is an attribute on <html>, which LiveView never patches.
const isTyping = (el) =>
  !!el && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName))

const updateJumpMode = () =>
  document.documentElement.toggleAttribute("data-jump-on", !isTyping(document.activeElement))

document.addEventListener("focusin", updateJumpMode)
// On focusout the new element isn't focused yet; check on the next frame.
document.addEventListener("focusout", () => requestAnimationFrame(updateJumpMode))
updateJumpMode()

window.addEventListener("keydown", (e) => {
  const el = document.activeElement
  // Another handler (e.g. the watchlist filter's flash labels) already acted on this key.
  if (e.defaultPrevented) return
  if (e.ctrlKey || e.metaKey || e.altKey) return

  if (isTyping(el)) {
    if (e.key === "Escape") el.blur()
    // Enter in a field would submit its form with the first button (Buy!). Not here.
    if (e.key === "Enter" && el.tagName === "INPUT" && el.form) e.preventDefault()
    return
  }

  if (e.key.length !== 1) return
  // Only inputs you can see (a closed exit panel's inputs aren't in the page at all).
  const target = [...document.querySelectorAll(`[data-jump="${CSS.escape(e.key)}"]`)].find(
    (input) => input.offsetParent !== null && !input.disabled
  )
  if (target) {
    e.preventDefault()
    // An input is focused (value selected, ready to retype). The only buttons with a key are the
    // exit-panel headers, which just open a panel, so for them the key is a click.
    if (target.tagName === "BUTTON") {
      target.click()
    } else {
      target.focus()
      target.select?.()
    }
  }
})

// Jump keys for the Move boxes in Open orders, given only to the boxes you can see right now.
// A fixed letter per order would run out once the list is long, and letters on boxes scrolled
// out of sight are useless anyway. So on every scroll, resize or change to the list, the
// visible Move boxes get letters from MOVE_KEYS in top-to-bottom order and the rest lose theirs.
// The letters go on through liveSocket.js().setAttribute, which LiveView keeps across patches
// (the card re-renders as prices tick). The global keydown handler above then finds them by
// data-jump like any other input; the label shows the letter via CSS attr(data-key).
const MOVE_KEYS = "hjkmoprvwyzcu" // not used by the fixed keys (b s q e x t n, a d f g); no l or i

const MoveKeys = {
  mounted() {
    this.queued = false
    this.schedule = () => {
      if (this.queued) return
      this.queued = true
      requestAnimationFrame(() => { this.queued = false; this.assign() })
    }
    this.el.addEventListener("scroll", this.schedule, {passive: true})
    window.addEventListener("scroll", this.schedule, {passive: true})
    window.addEventListener("resize", this.schedule)
    // New, filled or cancelled orders change the list.
    this.observer = new MutationObserver(this.schedule)
    this.observer.observe(this.el, {childList: true, subtree: true})
    this.schedule()
  },
  destroyed() {
    window.removeEventListener("scroll", this.schedule)
    window.removeEventListener("resize", this.schedule)
    this.observer?.disconnect()
  },
  assign() {
    const js = liveSocket.js()
    const box = this.el.getBoundingClientRect()
    const top = Math.max(box.top, 0)
    const bottom = Math.min(box.bottom, window.innerHeight)
    let next = 0
    for (const input of this.el.querySelectorAll("input[name=trigger]")) {
      const label = input.parentElement.querySelector(".move-label")
      const r = input.getBoundingClientRect()
      const visible = r.height > 0 && r.top >= top && r.bottom <= bottom
      const key = visible && next < MOVE_KEYS.length ? MOVE_KEYS[next++] : null
      if (key) {
        if (input.getAttribute("data-jump") !== key) js.setAttribute(input, "data-jump", key)
        if (label && label.getAttribute("data-key") !== key) js.setAttribute(label, "data-key", key)
      } else {
        if (input.hasAttribute("data-jump")) js.removeAttribute(input, "data-jump")
        if (label?.hasAttribute("data-key")) js.removeAttribute(label, "data-key")
      }
    }
  },
}

// Glossary popup (2026-11-08). Space twice in quick succession opens it, Esc closes it. The
// server renders the terms once inside phx-update="ignore", so this hook can show, hide and
// reorder rows directly: LiveView never patches them back.
//
// No state on purpose: open() and close() both reset() to a blank filter and the intro, so
// reopening never lands on the last term you read.
//
// Keys are handled in one capturing listener on window, which runs before every other key
// handler on the page (the jump keys, "/", the watchlist filter). While the glossary is open
// it claims every key, so nothing behind the blur reacts. While closed it only watches Space.
// The filter is the watchlist's (rank and assignLabels from flash.js): a letter that would
// continue the search is never a label, every other letter labels a match, best match first.
// One difference: Backspace clears the whole filter rather than one character.
const DOUBLE_SPACE_MS = 400

// Where Space types a character, so it must keep working: text boxes. A number box ignores
// Space anyway, so Space Space works from there too.
const typesSpace = (el) =>
  !!el && (el.isContentEditable || el.tagName === "TEXTAREA" || el.tagName === "SELECT" ||
    (el.tagName === "INPUT" && ["text", "search", "email", "url", "tel", "password"].includes(el.type)))

const Glossary = {
  mounted() {
    this.panel = this.el.querySelector("[data-glossary-panel]")
    this.input = this.el.querySelector("[data-glossary-input]")
    this.list = this.el.querySelector("[data-glossary-list]")
    this.detail = this.el.querySelector("[data-glossary-detail]")
    this.intro = this.el.querySelector("[data-glossary-intro]")
    this.empty = this.el.querySelector("[data-glossary-empty]")
    this.count = this.el.querySelector("[data-glossary-count]")
    this.items = [...this.el.querySelectorAll("[data-term-id]")]
    // flash.js speaks "rows" with a ticker and a name: here the term and its aliases.
    this.rows = this.items.map((li) => ({ticker: li.dataset.term, name: li.dataset.aliases, li}))
    this.lastSpace = 0
    this.labels = new Map()
    this.matches = []

    this.onKey = (e) => this.key(e)
    window.addEventListener("keydown", this.onKey, {capture: true})
    this.input.addEventListener("input", () => this.filter())
    this.el.addEventListener("glossary:open", () => this.open())
    this.el.addEventListener("click", (e) => {
      if (e.target.closest("[data-glossary-backdrop]")) return this.close()
      const goto = e.target.closest("[data-goto]")?.dataset.goto
      const row = e.target.closest("[data-term-id]")?.dataset.termId
      if (goto || row) this.show(goto || row)
      // Keep typing in the filter after a click.
      if (this.isOpen()) this.input.focus()
    })
  },
  destroyed() {
    window.removeEventListener("keydown", this.onKey, {capture: true})
    document.documentElement.style.overflow = ""
  },

  isOpen() { return !this.panel.classList.contains("hidden") },

  key(e) {
    if (this.isOpen()) return this.keyWhileOpen(e)
    if (e.key !== " " || e.ctrlKey || e.metaKey || e.altKey || typesSpace(e.target)) {
      this.lastSpace = 0
      return
    }
    // Space outside a text box would scroll the page, or press a focused button (an order
    // button!). Claim it either way.
    e.preventDefault()
    if (e.repeat) return
    const now = performance.now()
    if (now - this.lastSpace < DOUBLE_SPACE_MS) {
      e.stopImmediatePropagation()
      this.lastSpace = 0
      this.open()
    } else {
      this.lastSpace = now
    }
  },

  keyWhileOpen(e) {
    // Nothing behind the glossary sees a key while it's open.
    e.stopImmediatePropagation()
    const claim = () => e.preventDefault()
    if (e.key === "Escape") { claim(); return this.close() }
    if (e.key === "Backspace") { claim(); return this.clear() }
    if (e.key === "Enter") { claim(); if (this.matches[0]) this.show(this.matches[0].li.dataset.termId); return }
    // Tab would walk out into the page behind the blur.
    if (e.key === "Tab") { claim(); this.input.focus(); return }
    if (e.ctrlKey || e.metaKey || e.altKey || e.key.length !== 1) return

    const label = [...this.labels].find(([, key]) => key === e.key)?.[0]
    if (label) {
      claim()
      return this.show(this.rows.find((r) => r.ticker === label).li.dataset.termId)
    }
    // A character typed while focus is elsewhere in the dialog still goes into the filter.
    if (e.target !== this.input) {
      claim()
      this.input.focus()
      this.input.value += e.key
      this.filter()
    }
  },

  open() {
    this.reset()
    this.returnFocus = document.activeElement
    this.panel.classList.remove("hidden")
    document.documentElement.style.overflow = "hidden"
    this.input.focus()
  },

  close() {
    this.panel.classList.add("hidden")
    document.documentElement.style.overflow = ""
    this.reset()
    const back = this.returnFocus
    this.returnFocus = null
    if (back && back !== document.body && document.contains(back)) back.focus()
    else document.activeElement?.blur()
  },

  reset() {
    this.input.value = ""
    this.filter()
    this.select(null)
    this.list.scrollTop = 0
    this.detail.scrollTop = 0
  },

  clear() {
    this.input.value = ""
    this.filter()
  },

  filter() {
    const query = this.input.value.trim()
    this.matches = query ? rank(query, this.rows) : this.rows
    this.labels = assignLabels(query, this.matches, this.rows)
    const shown = new Map(this.matches.map((row, i) => [row.li, i]))
    for (const row of this.rows) {
      const at = shown.get(row.li)
      row.li.hidden = at === undefined
      row.li.style.order = at ?? ""
      const key = this.labels.get(row.ticker)
      const label = row.li.querySelector(".flash-label")
      label.textContent = key || ""
      label.style.display = key ? "inline-flex" : ""
    }
    this.empty.hidden = this.matches.length > 0
    this.count.textContent = query
      ? `${this.matches.length} match${this.matches.length === 1 ? "" : "es"}`
      : `${this.rows.length} terms`
    this.list.scrollTop = 0
  },

  // Open a term: like a watchlist jump, the filter clears and the list comes back whole, with
  // the term highlighted and scrolled into view.
  show(id) {
    this.clear()
    this.select(id)
    this.detail.scrollTop = 0
    document.getElementById(`glossary-${id}`)?.scrollIntoView({block: "nearest"})
  },

  select(id) {
    for (const li of this.items) li.toggleAttribute("aria-current", li.dataset.termId === id)
    for (const article of this.el.querySelectorAll("[data-detail]")) article.hidden = article.dataset.detail !== id
    this.intro.hidden = id !== null
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  // A function, so it runs on every (re)connect: a new LiveView process gets the latest
  // autosave and restores the portfolio in mount, before the first render.
  params: () => ({_csrf_token: csrfToken, save: storage.get(saveKey(pageSource()))}),
  hooks: {LocalTime, TimeZone, Chart, SaveFile, Flash, MoveKeys, Glossary}
})

liveSocket.connect()

// Apple-style scrollbars: the thumb pops in while an element scrolls and fades out after
// (CSS in app.css).
// Scroll events don't bubble, so one capturing listener on document sees every scroller. The
// class goes on through liveSocket.js(), which LiveView keeps across patches; a plain classList
// change would be wiped the next time that element re-renders (the watchlist does every tick).
const hideTimers = new WeakMap()

document.addEventListener(
  "scroll",
  (e) => {
    const el = e.target === document ? document.documentElement : e.target
    if (!(el instanceof Element)) return
    // .sb carries the fade-out transition; added once and kept, so the fade can run after
    // .is-scrolling comes off.
    if (!hideTimers.has(el)) liveSocket.js().addClass(el, ["sb", "is-scrolling"])
    clearTimeout(hideTimers.get(el))
    hideTimers.set(el, setTimeout(() => {
      liveSocket.js().removeClass(el, "is-scrolling")
      hideTimers.delete(el)
    }, 900))
  },
  {capture: true, passive: true}
)

// Handy in the browser console: liveSocket.enableDebug() logs every diff.
window.liveSocket = liveSocket

// Light/dark toggle. A pure client-side preference: no server round trip, no LiveView event.
// The inline script in root.html.heex applies the saved theme before first paint.
document.getElementById("theme-toggle")?.addEventListener("click", () => {
  const root = document.documentElement
  const theme = root.dataset.theme === "dark" ? "light" : "dark"
  root.dataset.theme = theme
  storage.set("theme", theme)
})
