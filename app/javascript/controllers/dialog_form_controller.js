import { Controller } from "@hotwired/stimulus"

// A form living inside a <dialog>, handling what happens once it saves.
//
// A "new record" form — which the Turbo Stream response leaves standing —
// blanks itself and stays open, so several entries can be made in a row
// without reopening the dialog. Anything else closes on success.
//
// Validation failures are left alone either way: the dialog stays open with
// what the user typed and the errors rendered alongside it.
export default class extends Controller {
    static values = { clearOnSuccess: Boolean }

    submitEnd(event) {
        if (!event.detail?.success) return

        if (this.clearOnSuccessValue) {
            this.clearFields()
            this.focusFirstField()
        } else {
            this.element.closest("dialog")?.close()
        }
    }

    clearFields() {
        this.element.reset()

        // reset() restores the radios without firing `change`, which is what
        // the priority pills restyle themselves on.
        this.element.querySelectorAll("input[type=radio]:checked").forEach(radio => {
            radio.dispatchEvent(new Event("change", { bubbles: true }))
        })
    }

    // The dialog is still up, so put the cursor back at the top for the next one.
    focusFirstField() {
        this.element.querySelector("input[type=text], textarea")?.focus()
    }
}
