import { Controller } from "@hotwired/stimulus"

// Manage Chores' "+ Add a task": the link opens a one-line field. Enter
// saves (and the re-rendered list comes back with the field open again —
// open value — so tasks can be typed in a row); clicking away saves
// whatever was typed without reopening (keep_open=0, so focus stays where
// the click went), or just closes an empty field; Escape closes it.
export default class extends Controller {
    static targets = ["button", "form", "input", "keepOpen"]
    static values = { open: Boolean }

    connect() {
        if (this.openValue) this.open()
    }

    open() {
        this.buttonTarget.classList.add("hidden")
        this.formTarget.classList.remove("hidden")
        this.inputTarget.focus()
    }

    close(event) {
        event?.preventDefault()
        this.inputTarget.value = ""
        this.formTarget.classList.add("hidden")
        this.buttonTarget.classList.remove("hidden")
    }

    submitting() {
        this.submitted = true
    }

    blur() {
        if (this.submitted) return
        if (this.inputTarget.value.trim() === "") {
            this.close()
        } else {
            this.keepOpenTarget.value = "0"
            this.formTarget.requestSubmit()
        }
    }
}
