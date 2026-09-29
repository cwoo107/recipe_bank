import { Controller } from "@hotwired/stimulus"

// A table cell that reads as plain text until clicked, then swaps in its
// field. Clicking away (or Enter, or picking a select option) saves by
// submitting the field's form — the field is tied to the row's form via its
// `form` attribute — and swaps the text back in with the new value. Escape
// cancels. Used by Manage Chores (chores/_table_row.html.erb).
export default class extends Controller {
    static targets = ["display", "text", "editor", "field"]

    edit() {
        if (this.editing) return
        this.editing = true
        this.original = this.fieldTarget.value

        this.displayTarget.classList.add("hidden")
        this.editorTarget.classList.remove("hidden")
        this.fieldTarget.focus()
        if (this.fieldTarget.tagName === "SELECT") {
            try { this.fieldTarget.showPicker() } catch { /* not supported — focus is enough */ }
        } else {
            this.fieldTarget.select?.()
        }
    }

    // blur, or change on a select.
    commit() {
        if (!this.editing) return
        this.editing = false

        const field = this.fieldTarget
        if (field.required && field.value.trim() === "") field.value = this.original

        this.#close()
        if (field.value === this.original) return

        this.textTarget.textContent = this.#label()
        field.form?.requestSubmit()
    }

    // Enter in a text field: save without also submitting the form natively.
    commitOnEnter(event) {
        event.preventDefault()
        this.commit()
        this.displayTarget.focus()
    }

    cancel(event) {
        event.preventDefault()
        if (!this.editing) return
        this.editing = false
        this.fieldTarget.value = this.original
        this.#close()
        this.displayTarget.focus()
    }

    #close() {
        this.editorTarget.classList.add("hidden")
        this.displayTarget.classList.remove("hidden")
    }

    #label() {
        const field = this.fieldTarget
        if (field.tagName === "SELECT") return field.selectedOptions[0]?.text ?? ""
        return field.value
    }
}
