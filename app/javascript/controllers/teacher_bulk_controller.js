import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "count", "submit", "selection", "selectAll", "operationSubmit", "selectionCount"]

  connect() {
    this.submitting = false
    this.beforeCache = () => this.resetSelection()
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.statusObserver = new MutationObserver((mutations) => this.syncStatusMutations(mutations))
    this.statusObserver.observe(this.element, { childList: true, subtree: true })
    this.rowTargets.forEach((row) => {
      this.filterRow(row)
      row.dataset.initialValues = JSON.stringify(this.valuesFor(row))
    })
    this.updateCount()
    this.resetSelection()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.statusObserver.disconnect()
  }

  filter(event) {
    const row = event.target.closest("[data-teacher-bulk-target='row']")
    this.filterRow(row)
    this.trackRow(row)
  }

  track(event) {
    this.trackRow(event.target.closest("[data-teacher-bulk-target='row']"))
  }

  trackRow(row) {
    if (!row.dataset.initialValues) return

    const initialValues = JSON.parse(row.dataset.initialValues)
    const fields = this.trackedFields(row)
    let dirty = false

    fields.forEach((field) => {
      const key = this.fieldKey(field)
      const changed = field.value !== initialValues[key]
      dirty ||= changed
      field.classList.toggle("border-amber-400", changed)
      field.classList.toggle("bg-amber-50", changed)
      field.classList.toggle("bg-white", !changed)
    })

    row.classList.toggle("bg-amber-50", dirty)
  }

  valuesFor(row) {
    return Object.fromEntries(this.trackedFields(row).map((field) => [this.fieldKey(field), field.value]))
  }

  trackedFields(row) {
    return Array.from(row.querySelectorAll("input[name$='[name]'], input[name$='[login_id]'], select[name$='[grade]'], select[name$='[classroom_id]']"))
  }

  fieldKey(field) {
    return field.name.match(/\[([^\]]+)\]$/)[1]
  }

  filterRow(row) {
    const schoolField = row.querySelector("[data-teacher-bulk-target='school']")
    const gradeField = row.querySelector("[data-teacher-bulk-target='grade']")
    const classroom = row.querySelector("[data-teacher-bulk-target='classroom']")
    if (!gradeField || !classroom) return

    const grade = gradeField.value
    const schoolId = schoolField?.value

    Array.from(classroom.options).forEach((option) => {
      const matchesSchool = !schoolField || option.dataset.schoolId === schoolId
      const available = option.value === "" || (matchesSchool && option.dataset.grade === grade)
      option.hidden = !available
      option.disabled = !available
    })

    if (classroom.selectedOptions[0]?.disabled) classroom.value = ""
  }

  removeRow(event) {
    if (this.rowTargets.length <= 1) return

    event.currentTarget.closest("[data-teacher-bulk-target='row']").remove()
    this.updateCount()
  }

  toggleAll(event) {
    this.selectionTargets.forEach((checkbox) => { checkbox.checked = event.currentTarget.checked })
    this.updateSelection()
  }

  updateSelection() {
    const selected = this.selectionTargets.filter((checkbox) => checkbox.checked).length
    this.operationSubmitTargets.forEach((button) => { button.disabled = selected === 0 })
    if (this.hasSelectionCountTarget) this.selectionCountTarget.textContent = `${selected}명 선택`
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = selected > 0 && selected === this.selectionTargets.length
      this.selectAllTarget.indeterminate = selected > 0 && selected < this.selectionTargets.length
    }
  }

  resetSelection() {
    this.selectionTargets.forEach((checkbox) => { checkbox.checked = false })
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = false
      this.selectAllTarget.indeterminate = false
    }
    this.updateSelection()
  }

  syncStatusMutations(mutations) {
    mutations.flatMap((mutation) => Array.from(mutation.addedNodes)).forEach((node) => {
      if (!(node instanceof Element)) return
      const status = node.matches("[data-teacher-active-state]") ? node : node.querySelector("[data-teacher-active-state]")
      if (status) this.syncActiveRow(status)
    })
  }

  syncActiveRow(status) {
    const row = status.closest("[data-teacher-bulk-target='row']")
    if (!row) return

    const active = status.dataset.teacherActiveState === "true"
    row.classList.toggle("bg-stone-50", !active)
    row.classList.toggle("text-stone-400", !active)
    this.trackedFields(row).forEach((field) => { field.disabled = !active })
    const idField = row.querySelector("input[name$='[id]']")
    if (idField) idField.disabled = !active

    if (!active) {
      const classroom = row.querySelector("select[name$='[classroom_id]']")
      if (classroom) classroom.value = ""
      const initialValues = JSON.parse(row.dataset.initialValues)
      initialValues.classroom_id = ""
      row.dataset.initialValues = JSON.stringify(initialValues)
    }
    this.trackRow(row)
  }

  submitOnce(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }

    this.submitting = true
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = true
    this.submitTarget.value = "등록 중..."
  }

  updateCount() {
    if (this.hasCountTarget) this.countTarget.textContent = `${this.rowTargets.length}명`
  }
}
