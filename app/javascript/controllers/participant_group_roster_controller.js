import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  removeRow(event) {
    const row = event.currentTarget.closest('[data-participant-group-roster-target="row"]')
    if (!row) return

    const destroyInput = row.querySelector('[data-participant-group-roster-target="destroy"]')
    if (destroyInput) {
      destroyInput.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }
  }
}
