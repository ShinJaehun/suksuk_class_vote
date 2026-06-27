import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notice"]

  static values = {
    url: String,
    windowName: String
  }

  connect() {
    window.electionBallotWindows ||= {}
    this.ballotWindow = window.electionBallotWindows[this.windowNameValue]
  }

  open(event) {
    event.preventDefault()

    if (this.ballotWindow && !this.ballotWindow.closed) {
      this.ballotWindow.focus()
      this.showNotice("투표 화면이 이미 열려 있습니다. 기존 투표 화면을 사용해 주세요.")
      return
    }

    this.ballotWindow = window.open(this.urlValue, this.windowNameValue)

    if (this.ballotWindow) {
      window.electionBallotWindows[this.windowNameValue] = this.ballotWindow
      this.ballotWindow.focus()
    } else {
      this.showNotice("팝업이 차단되어 투표 화면을 열 수 없습니다. 브라우저 팝업 설정을 확인해 주세요.")
    }
  }

  showNotice(message) {
    if (!this.hasNoticeTarget) return

    this.noticeTarget.textContent = message
    this.noticeTarget.hidden = false
  }
}
