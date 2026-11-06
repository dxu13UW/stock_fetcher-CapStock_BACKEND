// Connects this page to its LiveView process over the /live WebSocket.
// This is all the client-side JavaScript a basic LiveView page needs;
// the server sends HTML diffs and phoenix_live_view patches the DOM.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken}
})

liveSocket.connect()

// Handy in the browser console: liveSocket.enableDebug() logs every diff.
window.liveSocket = liveSocket

// Light/dark toggle. A pure client-side preference: no server round trip, no LiveView event.
// The inline script in root.html.heex applies the saved theme before first paint.
document.getElementById("theme-toggle")?.addEventListener("click", () => {
  const root = document.documentElement
  const theme = root.dataset.theme === "dark" ? "light" : "dark"
  root.dataset.theme = theme
  try { localStorage.setItem("theme", theme) } catch (_) {}
})
