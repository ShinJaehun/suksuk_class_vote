import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "school", "grade", "teacher", "selection", "selectAll", "selectionCount", "operationSubmit", "gradeSubmit", "gradeReason", "count", "submit"]

  connect() {
    this.submitting = false
    this.rowTargets.forEach((row) => {
      this.filterRowTeachers(row)
      if (row.dataset.trackDirty === "true") row.dataset.initialValues = JSON.stringify(this.valuesFor(row))
    })
    this.updateSelection()
    this.updateCount()
  }

  filterTeachers(event) {
    const row = event.target.closest("[data-classroom-management-target='row']")
    this.filterRowTeachers(row)
    this.trackRow(row)
  }

  filterRowTeachers(row) {
    const grade = row.querySelector("[data-classroom-management-target='grade']")?.value
    const school = row.querySelector("[data-classroom-management-target='school']")
    const schoolId = school?.value
    const teacher = row.querySelector("[data-classroom-management-target='teacher']")
    if (!grade || !teacher) return

    const classroomId = row.querySelector("input[name$='[id]']")?.value || ""
    Array.from(teacher.options).forEach((option) => {
      const currentAssignment = classroomId !== "" && option.dataset.classroomId === classroomId
      const matchesSchool = !school || (schoolId !== "" && option.dataset.schoolId === schoolId)
      const available = option.value === "" || currentAssignment || (matchesSchool && option.dataset.grade === grade && !option.dataset.classroomId)
      option.hidden = !available
      option.disabled = !available
    })
    if (teacher.selectedOptions[0]?.disabled) teacher.value = ""
  }

  toggleAll(event) {
    this.selectionTargets.forEach((checkbox) => { checkbox.checked = event.currentTarget.checked })
    this.updateSelection()
  }

  updateSelection() {
    const selected = this.selectionTargets.filter((checkbox) => checkbox.checked).length
    const gradeIneligible = this.selectionTargets.some((checkbox) => checkbox.checked && checkbox.dataset.gradeEligible !== "true")
    if (this.hasSelectionCountTarget) this.selectionCountTarget.textContent = `${selected}개 선택`
    this.operationSubmitTargets.forEach((button) => { button.disabled = selected === 0 })
    this.gradeSubmitTargets.forEach((button) => { button.disabled = selected === 0 || gradeIneligible })
    this.gradeReasonTargets.forEach((reason) => reason.classList.toggle("hidden", !gradeIneligible))
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = selected > 0 && selected === this.selectionTargets.length
      this.selectAllTarget.indeterminate = selected > 0 && selected < this.selectionTargets.length
    }
  }

  track(event) {
    this.trackRow(event.target.closest("[data-classroom-management-target='row']"))
  }

  trackRow(row) {
    if (!row?.dataset.initialValues) return

    const initialValues = JSON.parse(row.dataset.initialValues)
    let dirty = false
    this.trackedFields(row).forEach((field) => {
      const changed = field.value !== initialValues[field.name]
      dirty ||= changed
      field.classList.toggle("border-amber-400", changed)
      field.classList.toggle("bg-amber-50", changed)
      field.classList.toggle("bg-white", !changed)
    })
    row.classList.toggle("bg-amber-50", dirty)
  }

  valuesFor(row) {
    return Object.fromEntries(this.trackedFields(row).map((field) => [field.name, field.value]))
  }

  trackedFields(row) {
    return Array.from(row.querySelectorAll("select[name$='[grade]'], input[name$='[class_label]'], select[name$='[teacher_id]']"))
  }

  removeRow(event) {
    if (this.rowTargets.length <= 1) return

    event.currentTarget.closest("[data-classroom-management-target='row']").remove()
    this.updateCount()
  }

  updateCount() {
    if (this.hasCountTarget) this.countTarget.textContent = `${this.rowTargets.length}개`
  }

  submitOnce(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }
    this.submitting = true
    if (this.hasSubmitTarget) this.submitTarget.disabled = true
  }
}
