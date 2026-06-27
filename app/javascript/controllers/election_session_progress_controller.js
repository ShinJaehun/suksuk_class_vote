import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 2500 },
    url: String
  }

  connect() {
    this.pollTimer = window.setInterval(() => this.reloadFrame(), this.intervalValue)
  }

  disconnect() {
    window.clearInterval(this.pollTimer)
  }

  reloadFrame() {
    if (this.element.src) {
      this.element.reload()
    } else {
      this.element.src = this.urlValue
    }
  }
}
