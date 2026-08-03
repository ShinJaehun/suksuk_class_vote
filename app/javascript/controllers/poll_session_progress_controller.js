import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 2500 },
    url: String
  }

  connect() {
    this.reloadWhenVisible = this.reloadWhenVisible.bind(this)
    this.timer = window.setInterval(() => this.reloadFrame(), this.intervalValue)
    document.addEventListener("visibilitychange", this.reloadWhenVisible)
  }

  disconnect() {
    window.clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.reloadWhenVisible)
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
}
