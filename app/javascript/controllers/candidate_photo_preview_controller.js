import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "previewImage", "previewLabel", "removeCheckbox", "removeMessage", "submitButton", "loadingIndicator"]

  connect() {
    this.objectUrl = null
    this.originalPreviewSrc = this.hasPreviewImageTarget ? this.previewImageTarget.getAttribute("src") : null
    this.originalPreviewAlt = this.hasPreviewImageTarget ? this.previewImageTarget.getAttribute("alt") : ""
    this.originalPreviewLabel = this.hasPreviewLabelTarget ? this.previewLabelTarget.textContent.trim() : ""

    this.syncRemoveState()
  }

  disconnect() {
    this.revokeObjectUrl()
  }

  preview() {
    const file = this.selectedFile()

    this.revokeObjectUrl()

    if (!file) {
      this.restoreStoredPreview()
      this.syncRemoveState()
      return
    }

    if (!file.type.startsWith("image/")) {
      this.hidePreview()
      return
    }

    this.objectUrl = URL.createObjectURL(file)
    this.previewImageTarget.src = this.objectUrl
    this.previewImageTarget.alt = "새로 선택한 후보 사진"
    this.previewLabelTarget.textContent = "새로 선택한 사진"
    this.previewTarget.hidden = false
    this.previewTarget.classList.remove("opacity-50")

    if (this.hasRemoveCheckboxTarget) {
      this.removeCheckboxTarget.checked = false
    }

    if (this.hasRemoveMessageTarget) {
      this.removeMessageTarget.hidden = true
    }
  }

  toggleRemove() {
    if (this.hasSelectedFile()) {
      this.removeCheckboxTarget.checked = false
      return
    }

    this.syncRemoveState()
  }

  submit() {
    if (!this.hasSubmitButtonTarget) return

    this.originalSubmitLabel = this.submitButtonTarget.value
    this.submitButtonTarget.disabled = true
    this.submitButtonTarget.value = "저장 중..."
    if (this.hasLoadingIndicatorTarget) this.loadingIndicatorTarget.hidden = false
  }

  submitEnd() {
    if (!this.hasSubmitButtonTarget) return

    this.submitButtonTarget.disabled = false
    this.submitButtonTarget.value = this.originalSubmitLabel
    if (this.hasLoadingIndicatorTarget) this.loadingIndicatorTarget.hidden = true
  }

  syncRemoveState() {
    if (!this.hasRemoveCheckboxTarget || this.hasSelectedFile()) return

    if (this.removeCheckboxTarget.checked) {
      if (this.originalPreviewSrc) {
        this.previewTarget.hidden = false
        this.previewLabelTarget.textContent = "삭제 예정"
        this.previewTarget.classList.add("opacity-50")
      } else {
        this.hidePreview()
      }

      if (this.hasRemoveMessageTarget) {
        this.removeMessageTarget.hidden = false
      }
    } else {
      this.restoreStoredPreview()

      if (this.hasRemoveMessageTarget) {
        this.removeMessageTarget.hidden = true
      }
    }
  }

  restoreStoredPreview() {
    if (!this.originalPreviewSrc) {
      this.hidePreview()
      return
    }

    this.previewImageTarget.src = this.originalPreviewSrc
    this.previewImageTarget.alt = this.originalPreviewAlt
    this.previewLabelTarget.textContent = this.originalPreviewLabel || "현재 사진"
    this.previewTarget.hidden = false
    this.previewTarget.classList.remove("opacity-50")
  }

  hidePreview() {
    this.previewTarget.hidden = true
    this.previewTarget.classList.remove("opacity-50")

    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.removeAttribute("src")
    }
  }

  selectedFile() {
    return this.hasInputTarget ? this.inputTarget.files?.[0] : null
  }

  hasSelectedFile() {
    return Boolean(this.selectedFile())
  }

  revokeObjectUrl() {
    if (!this.objectUrl) return

    URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  }
}
