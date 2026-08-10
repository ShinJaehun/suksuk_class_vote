import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 10000 },
    pauseSelector: String,
    url: String
  }

  connect() {
    this.reloadWhenVisible = this.reloadWhenVisible.bind(this)
    this.syncPollingState = this.syncPollingState.bind(this)
    this.element.addEventListener("turbo:frame-render", this.syncPollingState)
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
    this.element.removeEventListener("turbo:frame-render", this.syncPollingState)
  }

  reloadFrame() {
    if (this.element.src) {
      this.element.reload()
    } else {
      this.element.src = this.urlValue
    }
  }

  reloadWhenVisible() {
    if (document.hidden) return

    this.reloadFrame()
  }

  syncPollingState() {
    if (this.element.querySelector(this.pauseSelectorValue)) this.stopPolling()
  }

  startPolling() {
    if (this.timer) return

    this.timer = window.setInterval(() => this.reloadFrame(), this.intervalValue)
    document.addEventListener("visibilitychange", this.reloadWhenVisible)
  }

  stopPolling() {
    window.clearInterval(this.timer)
    this.timer = null
    document.removeEventListener("visibilitychange", this.reloadWhenVisible)
  }
}
