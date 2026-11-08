// Fuzzy filter + flash.nvim-style jump labels for the watchlist. Pure functions, no DOM, so
// the rules are easy to read (and to check in Node). The Flash hook in app.js uses them.

// Home row first, like flash.nvim: the keys under your fingers get the best matches.
// No "l" or "i": in many fonts they look alike (or like 1).
export const LABEL_KEYS = "asdfghjkqwertyuopzxcvbnm"

const isWordStart = (text, i) => i === 0 || /[^a-z0-9]/.test(text[i - 1])

// How well `query` matches `text`; -1 = no match, higher = better. Both lower case.
//   prefix ("nv" in "nvda")            best
//   substring at a word start ("motors" in "general motors")
//   substring anywhere
//   word-start subsequence ("jj" in "johnson & johnson", "dwave" in "d-wave quantum"): each
//   letter must come right after the previous one or start a word. Plain subsequences ("ap" in
//   "alphabet") don't count: they match almost anything, which would leave flash no free letters.
export function fuzzyScore(query, text) {
  if (!query) return 0
  const at = text.indexOf(query)
  if (at === 0) return 1000 - text.length
  if (at > 0) return (isWordStart(text, at) ? 800 : 600) - at

  let score = 300
  let prev = -1
  for (const ch of query) {
    let found = -1
    for (let i = prev + 1; i < text.length; i++) {
      if (text[i] === ch && (i === prev + 1 || isWordStart(text, i))) { found = i; break }
    }
    if (found < 0) return -1
    score += found === prev + 1 ? 10 : 0
    score -= found - prev - 1
    prev = found
  }
  return score
}

// A row's score: the better of its ticker and its company name. A ticker match gets a bonus,
// since typing "t" should rank T (AT&T) above "Tesla".
export function rowScore(query, row) {
  const q = query.toLowerCase()
  const ticker = fuzzyScore(q, row.ticker.toLowerCase())
  const name = fuzzyScore(q, row.name.toLowerCase())
  return Math.max(ticker < 0 ? -1 : ticker + 50, name)
}

// Rows that match, best first (ties keep alphabetical order).
export function rank(query, rows) {
  return rows
    .map((row) => ({row, score: rowScore(query, row)}))
    .filter((r) => r.score >= 0)
    .sort((a, b) => b.score - a.score || a.row.ticker.localeCompare(b.row.ticker))
    .map((r) => r.row)
}

// flash.nvim's rule: a letter that would *continue* the search (query + letter still matches
// some row) can't be a label, or typing it would be ambiguous. Every other letter labels a
// match, best match first. Returns Map(ticker -> letter); with more matches than free letters,
// the rest get no label.
export function assignLabels(query, matches, rows) {
  if (!query) return new Map()
  const free = [...LABEL_KEYS].filter((key) => rank(query + key, rows).length === 0)
  return new Map(matches.slice(0, free.length).map((row, i) => [row.ticker, free[i]]))
}
