import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["contest", "submit", "card", "stamp"]

  connect() {
    this.transitioning = false
    this.contestTargets.forEach((contest) => this.syncContestSelection(contest))
  }

  choose(event) {
    if (this.transitioning) return

    const choice = document.getElementById(event.params.choiceId)
    if (!choice) return

    choice.checked = true

    const currentIndex = this.contestTargets.findIndex((contest) => !contest.hidden)
    const currentContest = this.contestTargets[currentIndex]
    if (!currentContest) return

    this.transitioning = true
    this.syncContestSelection(currentContest)

    const nextContest = this.contestTargets[currentIndex + 1]

    window.setTimeout(() => {
      if (nextContest) {
        currentContest.hidden = true
        nextContest.hidden = false
        this.syncContestSelection(nextContest)
        this.transitioning = false
        return
      }

      this.element.requestSubmit(this.submitTarget)
    }, 320)
  }

  syncContestSelection(contest) {
    this.cardsFor(contest).forEach((card) => {
      const choice = document.getElementById(card.dataset.electionBallotChoiceIdParam)
      const selected = choice?.checked === true

      card.classList.toggle("border-emerald-600", selected)
      card.classList.toggle("bg-emerald-50", selected)
      card.classList.toggle("shadow-lg", selected)
      card.classList.toggle("ring-2", selected)
      card.classList.toggle("ring-emerald-500", selected)
      card.classList.toggle("scale-[1.01]", selected)

      card.classList.toggle("border-stone-200", !selected)
      card.classList.toggle("bg-white", !selected)
      card.classList.toggle("shadow-sm", !selected)

      const stamp = card.querySelector("[data-election-ballot-target~='stamp']")
      if (stamp) {
        stamp.classList.toggle("opacity-100", selected)
        stamp.classList.toggle("scale-100", selected)
        stamp.classList.toggle("opacity-0", !selected)
        stamp.classList.toggle("scale-75", !selected)
      }
    })
  }

  cardsFor(contest) {
    return this.cardTargets.filter((card) => contest.contains(card))
  }
}
