import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "gradeCheckbox",
    "classCheckbox"
  ]

  connect() {
    this.refresh()
  }

  toggleGrade(event) {
    const grade = event.currentTarget.dataset.grade

    this.classCheckboxTargets
      .filter((checkbox) => checkbox.dataset.grade === grade)
      .forEach((checkbox) => {
        checkbox.checked = event.currentTarget.checked
      })

    this.refresh()
  }

  toggleClass() {
    this.refresh()
  }

  refresh() {
    this.gradeCheckboxTargets.forEach((gradeCheckbox) => {
      const classCheckboxes = this.classCheckboxTargets.filter((checkbox) => {
        return checkbox.dataset.grade === gradeCheckbox.dataset.grade
      })
      const checkedCount = classCheckboxes.filter((checkbox) => checkbox.checked).length

      gradeCheckbox.checked = checkedCount === classCheckboxes.length
      gradeCheckbox.indeterminate = checkedCount > 0 && checkedCount < classCheckboxes.length
    })
  }
}
