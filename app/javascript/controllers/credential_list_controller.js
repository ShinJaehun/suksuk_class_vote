import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row"]
  static values = { returnUrl: String }

  connect() {
    if (this.hasReturnUrlValue) window.history.replaceState(window.history.state, "", this.returnUrlValue)
  }

  copyAll(event) {
    const header = "이름\t로그인 ID\t임시 비밀번호"
    this.copy([header, ...this.rowTargets.map((row) => row.dataset.copyText)].join("\n"), event.currentTarget)
  }

  copyRow(event) {
    const row = event.currentTarget.closest("[data-credential-list-target='row']")
    this.copy(row.dataset.copyText, event.currentTarget)
  }

  print() {
    window.print()
  }

  async copy(text, button) {
    await navigator.clipboard.writeText(text)
    const original = button.textContent
    button.textContent = "복사됨"
    window.setTimeout(() => { button.textContent = original }, 1200)
  }
}
