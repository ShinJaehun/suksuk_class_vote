import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "row", "number", "position", "up", "down"]

  connect() {
    this.refresh()
  }

  up(event) {
    const row = event.currentTarget.closest("[data-student-rows-target='row']")
    if (row.previousElementSibling) {
      this.swapNumbers(row, row.previousElementSibling)
      this.listTarget.insertBefore(row, row.previousElementSibling)
    }
    this.refresh()
  }

  down(event) {
    const row = event.currentTarget.closest("[data-student-rows-target='row']")
    if (row.nextElementSibling) {
      this.swapNumbers(row, row.nextElementSibling)
      this.listTarget.insertBefore(row.nextElementSibling, row)
    }
    this.refresh()
  }

  remove(event) {
    const row = event.currentTarget.closest("[data-student-rows-target='row']")
    row.remove()
    this.refresh()
  }

  refresh() {
    const rows = this.rowTargets
    rows.forEach((row, index) => {
      row.querySelector("[data-student-rows-target='position']").value = index
      row.querySelector("[data-student-rows-target='up']").disabled = index === 0
      row.querySelector("[data-student-rows-target='down']").disabled = index === rows.length - 1
    })
  }

  swapNumbers(firstRow, secondRow) {
    const first = firstRow.querySelector("[data-student-rows-target='number']")
    const second = secondRow.querySelector("[data-student-rows-target='number']")
    const firstValue = first.value
    first.value = second.value
    second.value = firstValue
  }
}
