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
