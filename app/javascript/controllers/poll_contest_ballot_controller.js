import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["choice", "card", "stamp", "warning", "submit"]

  connect() {
    this.transitioning = false
    this.submitting = false
    this.syncSelection()
  }

  choose(event) {
    if (this.transitioning || this.submitting) return

    const choice = document.getElementById(event.params.choiceId)
    if (!choice) return

    this.choiceTargets.forEach((input) => {
      input.checked = input === choice
    })
    this.hideWarning()
    this.syncSelection()
  }

  submitContest() {
    if (this.transitioning || this.submitting) return

    if (!this.selectedChoice()) {
      this.showWarning()
      return
    }

    this.transitioning = true
    this.syncSelection()

    window.setTimeout(() => {
      this.element.requestSubmit(this.submitTarget)
    }, 320)
  }

  submit(event) {
    if (this.submitting) {
      event.preventDefault()
      event.stopImmediatePropagation()
      return
    }

    this.submitting = true
    this.element.setAttribute("aria-busy", "true")

    queueMicrotask(() => {
      this.element.querySelectorAll("button, input[type='submit']").forEach((button) => {
        button.disabled = true
      })
    })
  }

  syncSelection() {
    this.cardTargets.forEach((card) => {
      const choice = document.getElementById(card.dataset.pollContestBallotChoiceIdParam)
      const selected = choice?.checked === true
      const abstain = choice?.name === "ballot[abstain]"

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

      const stamp = card.querySelector("[data-poll-contest-ballot-target~='stamp']")
      if (stamp) {
        stamp.classList.toggle("opacity-100", selected)
        stamp.classList.toggle("scale-100", selected)
        stamp.classList.toggle("opacity-0", !selected)
        stamp.classList.toggle("scale-75", !selected)
      }
    })
  }

  selectedChoice() {
    return this.choiceTargets.find((choice) => choice.checked)
  }

  showWarning() {
    this.warningTargets.forEach((warning) => warning.classList.remove("hidden"))
  }

  hideWarning() {
    this.warningTargets.forEach((warning) => warning.classList.add("hidden"))
  }
}
