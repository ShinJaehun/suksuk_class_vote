import { Controller } from "@hotwired/stimulus"

const ballotWindows = window.pollSessionBallotWindows ||= {}

export default class extends Controller {
  static values = { name: String }

  connect() {
    const ballotWindow = ballotWindows[this.nameValue]

    if (ballotWindow?.closed) {
      delete ballotWindows[this.nameValue]
    }
  }

  open(event) {
    event.preventDefault()

    const existingWindow = ballotWindows[this.nameValue]
    if (existingWindow && !existingWindow.closed) {
      existingWindow.focus()
      return
    }

    const ballotWindow = window.open(event.currentTarget.href, this.nameValue)
    if (ballotWindow) {
      ballotWindows[this.nameValue] = ballotWindow
      ballotWindow.focus()
    } else {
      window.alert("팝업이 차단되었습니다. 브라우저에서 팝업을 허용해 주세요.")
    }
  }
}
