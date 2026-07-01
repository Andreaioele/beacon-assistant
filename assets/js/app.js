// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/beacon_assistant"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const Hooks = {
  ChatAutoScroll: {
    mounted() {
      this.scrollToBottom()
    },
    updated() {
      this.scrollToBottom()
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight
    },
  },
  NetworkStatus: {
    mounted() {
      this.handleStatusChange = () => {
        const online = window.navigator.onLine
        this.applyClientNetworkState(online)
        this.pushEvent("network_status_changed", {online})
      }

      window.addEventListener("online", this.handleStatusChange)
      window.addEventListener("offline", this.handleStatusChange)
      this.handleStatusChange()
    },
    destroyed() {
      window.removeEventListener("online", this.handleStatusChange)
      window.removeEventListener("offline", this.handleStatusChange)
    },
    applyClientNetworkState(online) {
      this.el.querySelectorAll("input, button").forEach(element => {
        if (!online) {
          element.dataset.networkDisabled = element.disabled ? "true" : "false"
          element.disabled = true
        } else if (element.dataset.networkDisabled === "false") {
          element.disabled = false
          delete element.dataset.networkDisabled
        }
      })

      const existingMessage = this.el.querySelector("[data-client-offline-message]")

      if (online) {
        if (existingMessage) existingMessage.remove()
        return
      }

      if (existingMessage) return

      const message = document.createElement("p")
      message.dataset.clientOfflineMessage = "true"
      message.className = "mt-4 rounded-md bg-error/10 p-3 text-sm text-error"
      message.textContent = "You appear to be offline. Connect to the internet before sending a request."

      const form = this.el.querySelector("form")
      if (form) {
        form.insertAdjacentElement("beforebegin", message)
      } else {
        this.el.appendChild(message)
      }
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
