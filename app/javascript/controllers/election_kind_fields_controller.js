import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "singleContestFields"]

  connect() {
    this.toggle()
  }

  toggle() {
    this.singleContestFieldsTarget.hidden = this.kindTarget.value !== "school_council_single_contest"
  }
}
