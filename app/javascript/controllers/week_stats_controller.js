import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["panel", "overlay"]
    static values  = { open: { type: Boolean, default: false } }

    toggle() {
        this.openValue = !this.openValue
    }

    close() {
        this.openValue = false
    }

    openValueChanged() {
        this.panelTarget.classList.toggle("translate-x-full", !this.openValue)
        this.panelTarget.classList.toggle("translate-x-0", this.openValue)
        this.overlayTarget.classList.toggle("opacity-0", !this.openValue)
        this.overlayTarget.classList.toggle("pointer-events-none", !this.openValue)
        this.overlayTarget.classList.toggle("opacity-100", this.openValue)
    }
}