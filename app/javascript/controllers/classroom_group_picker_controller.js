import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["all", "item"]

  connect() {
    this.sync()
  }

  toggleAll() {
    this.itemTargets.forEach((checkbox) => {
      checkbox.checked = this.allTarget.checked
    })
    this.allTarget.indeterminate = false
  }

  sync() {
    const checkedCount = this.itemTargets.filter((checkbox) => checkbox.checked).length
    this.allTarget.checked = checkedCount === this.itemTargets.length
    this.allTarget.indeterminate = checkedCount > 0 && checkedCount < this.itemTargets.length
  }
}
