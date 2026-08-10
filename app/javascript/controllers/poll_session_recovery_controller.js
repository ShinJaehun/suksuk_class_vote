import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 10000 },
    targetId: String,
    url: String
  }

  connect() {
    this.checkWhenVisible = this.checkWhenVisible.bind(this)
    this.stopAfterTerminalRender = this.stopAfterTerminalRender.bind(this)
    this.timer = window.setInterval(() => this.check(), this.intervalValue)
    document.addEventListener("visibilitychange", this.checkWhenVisible)
    document.addEventListener("turbo:before-stream-render", this.stopAfterTerminalRender)
  }

  disconnect() {
    this.stop()
  }

  async check() {
    if (document.hidden || this.checking) return

    this.checking = true
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (response.status === 204 || !response.ok) return

      const stream = await response.text()
      if (stream) {
        window.Turbo.renderStreamMessage(stream)
        this.stop()
      }
    } catch (_error) {
      // A later probe can recover from a temporary network failure.
    } finally {
      this.checking = false
    }
  }

  checkWhenVisible() {
    if (!document.hidden) this.check()
  }

  stopAfterTerminalRender(event) {
    if (event.target.getAttribute("target") !== this.targetIdValue) return

    window.requestAnimationFrame(() => {
      if (document.getElementById(this.targetIdValue)?.querySelector("[data-poll-session-terminal]")) this.stop()
    })
  }

  stop() {
    window.clearInterval(this.timer)
    this.timer = null
    document.removeEventListener("visibilitychange", this.checkWhenVisible)
    document.removeEventListener("turbo:before-stream-render", this.stopAfterTerminalRender)
  }
}
