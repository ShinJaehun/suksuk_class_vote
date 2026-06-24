import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["contest", "submit", "card", "stamp", "warning"]

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

    this.hideWarning(currentContest)
    this.syncContestSelection(currentContest)
  }

  submitContest() {
    if (this.transitioning) return

    const currentIndex = this.contestTargets.findIndex((contest) => !contest.hidden)
    const currentContest = this.contestTargets[currentIndex]
    if (!currentContest) return

    if (!this.selectedChoiceFor(currentContest)) {
      this.showWarning(currentContest)
      return
    }

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
      const abstain = choice?.value === "abstain"

      card.classList.toggle("border-emerald-600", selected && !abstain)
      card.classList.toggle("bg-emerald-50", selected && !abstain)
      card.classList.toggle("ring-emerald-500", selected && !abstain)
      card.classList.toggle("border-amber-600", selected && abstain)
      card.classList.toggle("bg-amber-100", selected && abstain)
      card.classList.toggle("ring-amber-500", selected && abstain)
      card.classList.toggle("shadow-lg", selected)
      card.classList.toggle("ring-2", selected)
      card.classList.toggle("scale-[1.01]", selected)

      card.classList.toggle("border-stone-200", !selected && !abstain)
      card.classList.toggle("bg-white", !selected && !abstain)
      card.classList.toggle("border-amber-300", !selected && abstain)
      card.classList.toggle("bg-amber-50", !selected && abstain)
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

  selectedChoiceFor(contest) {
    return this.cardsFor(contest)
      .map((card) => document.getElementById(card.dataset.electionBallotChoiceIdParam))
      .find((choice) => choice?.checked === true)
  }

  showWarning(contest) {
    this.warningTargets
      .filter((warning) => contest.contains(warning))
      .forEach((warning) => warning.classList.remove("hidden"))
  }

  hideWarning(contest) {
    this.warningTargets
      .filter((warning) => contest.contains(warning))
      .forEach((warning) => warning.classList.add("hidden"))
  }
}
