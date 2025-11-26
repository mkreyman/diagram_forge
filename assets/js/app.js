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

// Alpine.js for Backpex admin panel
import Alpine from "alpinejs"
window.Alpine = Alpine
Alpine.start()
import {hooks as colocatedHooks} from "phoenix-colocated/diagram_forge"
import topbar from "../vendor/topbar"
import mermaid from "mermaid"

// Initialize Mermaid with default settings
mermaid.initialize({
  startOnLoad: false,
  theme: "default",
  securityLevel: "loose"
})

// Clean up orphaned Mermaid elements from document body
// Mermaid render() inserts SVGs into body when errors occur
function cleanupOrphanedMermaidElements() {
  // Remove any SVGs with mermaid- prefix IDs that are direct children of body
  document.querySelectorAll('body > svg[id^="mermaid-"]').forEach(el => el.remove())
  // Remove any standalone Mermaid error elements
  document.querySelectorAll('body > .mermaid-error, body > [id^="dmermaid-"]').forEach(el => el.remove())
}

// Mermaid LiveView Hook
const Mermaid = {
  mounted() {
    cleanupOrphanedMermaidElements()
    this.renderDiagram()
  },
  updated() {
    cleanupOrphanedMermaidElements()
    this.renderDiagram()
  },
  async renderDiagram() {
    const container = this.el.querySelector(".mermaid")
    if (!container) {
      console.warn("Mermaid hook: no .mermaid container found")
      return
    }

    const diagramCode = this.el.dataset.diagram
    if (!diagramCode) {
      console.warn("Mermaid hook: no diagram code in data-diagram attribute")
      return
    }

    // Store reference to hook for use in async callbacks
    const hook = this

    // Extract source hash from element ID (format: mermaid-preview-HASH)
    const sourceHash = parseInt(this.el.id.split('-').pop(), 10) || null

    // Get theme from data attribute
    const theme = this.el.dataset.theme || "light"
    const mermaidTheme = theme === "dark" ? "dark" : "default"

    // Reinitialize Mermaid with the selected theme
    mermaid.initialize({
      startOnLoad: false,
      theme: mermaidTheme,
      securityLevel: "loose"
    })

    // Generate unique ID for this render
    const diagramId = `mermaid-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`

    try {
      const { svg } = await mermaid.render(diagramId, diagramCode)
      container.innerHTML = svg
      // Clear any previous error state - use stored hook reference
      // Include sourceHash so server can match this to the expected fix
      hook.pushEvent("mermaid_render_success", { sourceHash })
    } catch (err) {
      // Extract useful error information
      const errorInfo = {
        message: err.message || String(err),
        // Mermaid includes hash with parsing details
        line: err.hash?.line,
        expected: err.hash?.expected ? err.hash.expected.join(", ") : null,
        // Get the mermaid version for context
        mermaidVersion: mermaid.version || "unknown",
        // Include sourceHash so server can match this to the expected fix
        sourceHash
      }

      // Send error to server for AI context - use stored hook reference
      try {
        hook.pushEvent("mermaid_render_error", errorInfo)
      } catch (pushErr) {
        console.error("Failed to push mermaid_render_error event:", pushErr)
      }

      // Display error in container
      container.innerHTML = `
        <div class="text-red-400 p-4 border border-red-700 rounded bg-red-950/50">
          <p class="font-bold text-sm mb-2">Syntax Error</p>
          <p class="text-xs font-mono break-all">${err.message || "Unknown error"}</p>
        </div>
      `
    } finally {
      // Clean up orphaned Mermaid error elements that render() leaves behind
      // Mermaid inserts error SVGs with the diagram ID into the document body
      const orphanedSvg = document.getElementById(diagramId)
      if (orphanedSvg && orphanedSvg.parentNode !== container) {
        orphanedSvg.remove()
      }
      // Also clean up any Mermaid error containers (class varies by version)
      document.querySelectorAll(`#d${diagramId}, .mermaid-error`).forEach(el => {
        if (el.parentNode !== container) {
          el.remove()
        }
      })
    }
  }
}

// Copy to Clipboard Hook
const CopyToClipboard = {
  mounted() {
    this.handleEvent("copy-to-clipboard", ({text}) => {
      navigator.clipboard.writeText(text).then(() => {
        // Visual feedback - briefly change button text
        const originalHTML = this.el.innerHTML
        this.el.innerHTML = `<svg class="w-3 h-3 inline-block mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
        </svg>Copied!`
        this.el.classList.remove("bg-green-800", "hover:bg-green-700")
        this.el.classList.add("bg-green-600")

        setTimeout(() => {
          this.el.innerHTML = originalHTML
          this.el.classList.remove("bg-green-600")
          this.el.classList.add("bg-green-800", "hover:bg-green-700")
        }, 2000)
      }).catch(err => {
        console.error("Failed to copy text: ", err)
      })
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Mermaid, CopyToClipboard},
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
    window.addEventListener("keyup", e => keyDown = null)
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

