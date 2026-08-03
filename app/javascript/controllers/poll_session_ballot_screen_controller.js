import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { closeUrl: String }

  connect() {
    this.notifyClosed = this.notifyClosed.bind(this)
    window.addEventListener("pagehide", this.notifyClosed)
  }

  disconnect() {
    window.removeEventListener("pagehide", this.notifyClosed)
  }

  notifyClosed() {
    if (this.closeNotified) return

    this.closeNotified = true
    const formData = new FormData()
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    }

    if (navigator.sendBeacon?.(this.closeUrlValue, formData)) return

    fetch(this.closeUrlValue, {
      method: "POST",
      body: formData,
      keepalive: true,
      credentials: "same-origin"
    })
  }
}
