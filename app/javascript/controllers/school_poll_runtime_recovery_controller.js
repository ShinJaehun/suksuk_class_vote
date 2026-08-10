import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 10000 },
    pauseSelector: String,
    url: String
  }

  connect() {
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.syncPollingState = this.syncPollingState.bind(this)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    this.element.addEventListener("turbo:frame-render", this.syncPollingState)
    this.syncPollingState()
  }

  disconnect() {
    this.stopPolling()
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.element.removeEventListener("turbo:frame-render", this.syncPollingState)
  }

  reloadFrame() {
    if (this.element.src) {
      this.element.reload()
    } else {
      this.element.src = this.urlValue
    }
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.stopPolling()
      return
    }

    if (this.pollingPaused()) {
      this.stopPolling()
      return
    }

    this.reloadFrame()
    this.startPolling()
  }

  syncPollingState() {
    if (document.hidden || this.pollingPaused()) {
      this.stopPolling()
    } else {
      this.startPolling()
    }
  }

  pollingPaused() {
    return this.hasPauseSelectorValue && this.element.querySelector(this.pauseSelectorValue)
  }

  startPolling() {
    if (this.timer) return

    this.timer = window.setInterval(() => this.reloadFrame(), this.intervalValue)
  }

  stopPolling() {
    window.clearInterval(this.timer)
    this.timer = null
  }
}
