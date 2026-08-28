import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Replaces the browser's native confirm() for every data-turbo-confirm="..."
// link/button/form across the app with this app-styled <dialog>. Nothing
// else needs to change — Turbo calls Turbo.config.forms.confirm(message)
// and awaits the returned promise before proceeding with (or cancelling)
// the action.
export default class extends Controller {
    static targets = ["message"]

    connect() {
        Turbo.config.forms.confirm = (message) => this.confirm(message)
    }

    confirm(message) {
        this.messageTarget.textContent = message

        return new Promise((resolve) => {
            this.resolve = resolve
            this.element.showModal()
        })
    }

    accept() {
        this.settle(true)
        this.element.close()
    }

    cancel() {
        this.settle(false)
        this.element.close()
    }

    // Native "cancel" event (Esc key) — the dialog closes itself, we just
    // need to settle the pending promise.
    handleCancel() {
        this.settle(false)
    }

    // A click that lands on the <dialog> element itself (not its content)
    // is a click on the ::backdrop.
    backdropClick(event) {
        if (event.target === this.element) this.cancel()
    }

    settle(result) {
        this.resolve?.(result)
        this.resolve = null
    }
}
