import { Controller } from "@hotwired/stimulus"

// Account settings' "Delete my account": opens a dialog whose delete button
// only enables once the phrase is typed exactly (the server checks it too —
// Users::RegistrationsController#destroy).
export default class extends Controller {
    static targets = ["dialog", "input", "submit"]
    static values = { phrase: String }

    open() {
        this.inputTarget.value = ""
        this.check()
        this.dialogTarget.showModal()
        this.inputTarget.focus()
    }

    close() {
        this.dialogTarget.close()
    }

    // A click on the backdrop (outside the dialog's box) closes it.
    backdropClick(event) {
        if (event.target === this.dialogTarget) this.close()
    }

    check() {
        this.submitTarget.disabled = this.inputTarget.value.trim() !== this.phraseValue
    }
}
