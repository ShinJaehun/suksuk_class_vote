import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { copyText: String }

  close() {
    this.element.closest("turbo-frame").replaceChildren()
  }

  async copy(event) {
    await navigator.clipboard.writeText(this.copyTextValue)
    event.currentTarget.textContent = "복사됨"
  }
}
