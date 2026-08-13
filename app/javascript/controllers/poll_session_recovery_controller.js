import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 10000 },
    targetId: String,
    url: String
  }

  connect() {
    this.stopped = false
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.stopAfterTerminalRender = this.stopAfterTerminalRender.bind(this)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    document.addEventListener("turbo:before-stream-render", this.stopAfterTerminalRender)
    this.startPolling()
  }

  disconnect() {
    this.stop()
  }

  async check() {
    if (document.hidden || this.checking) return

    this.checking = true
    try {
      const url = new URL(this.urlValue, window.location.origin)
      const target = document.getElementById(this.targetIdValue)
      if (target?.dataset.pollSessionRuntimeFingerprint) {
        url.searchParams.set("fingerprint", target.dataset.pollSessionRuntimeFingerprint)
      }
      const response = await fetch(url, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (response.status === 204 || !response.ok) return

      const stream = await response.text()
      if (stream) {
        window.Turbo.renderStreamMessage(stream)
      }
    } catch (_error) {
      // A later probe can recover from a temporary network failure.
    } finally {
      this.checking = false
    }
  }

  handleVisibilityChange() {
    if (this.stopped) return

    if (document.hidden) {
      this.stopPolling()
      return
    }

    this.check()
    this.startPolling()
  }

  stopAfterTerminalRender(event) {
    if (event.target.getAttribute("target") !== this.targetIdValue) return

    window.requestAnimationFrame(() => {
      if (document.getElementById(this.targetIdValue)?.querySelector("[data-poll-session-terminal]")) this.stop()
    })
  }

  stop() {
    this.stopped = true
    this.stopPolling()
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    document.removeEventListener("turbo:before-stream-render", this.stopAfterTerminalRender)
  }

  startPolling() {
    if (this.stopped || document.hidden || this.timer) return

    this.timer = window.setInterval(() => this.check(), this.intervalValue)
  }

  stopPolling() {
    window.clearInterval(this.timer)
    this.timer = null
  }
}
