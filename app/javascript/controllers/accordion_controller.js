import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["trigger", "content"]
    static values  = { open: { type: Boolean, default: false } }

    connect() {
        this.#applyState()
    }

    toggle() {
        this.openValue = !this.openValue
        this.#applyState()
    }

    open()  { this.openValue = true;  this.#applyState() }
    close() { this.openValue = false; this.#applyState() }

    #applyState() {
        const isOpen = this.openValue
        this.triggerTargets.forEach(t => t.setAttribute("aria-expanded", isOpen))
        this.contentTargets.forEach(c => {
            c.classList.toggle("accordion-open", isOpen)
            c.classList.toggle("accordion-closed", !isOpen)
        })
    }
}