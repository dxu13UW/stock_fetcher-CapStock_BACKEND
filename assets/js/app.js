// Connects this page to its LiveView process over the /live WebSocket.
// This is all the client-side JavaScript a basic LiveView page needs;
// the server sends HTML diffs and phoenix_live_view patches the DOM.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

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
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {LocalTime}
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
