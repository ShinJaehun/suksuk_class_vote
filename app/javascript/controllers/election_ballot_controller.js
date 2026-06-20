import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["contest", "submit"]

  choose(event) {
    const choice = document.getElementById(event.params.choiceId)
    if (!choice) return

    choice.checked = true

    const currentIndex = this.contestTargets.findIndex((contest) => !contest.hidden)
    const nextContest = this.contestTargets[currentIndex + 1]

    if (nextContest) {
      this.contestTargets[currentIndex].hidden = true
      nextContest.hidden = false
      return
    }

    this.element.requestSubmit(this.submitTarget)
  }
}
