import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card"]

  removeCard(event) {
    event.preventDefault()

    event.currentTarget.closest("[data-bulk-class-roster-target='card']")?.remove()
  }
}
