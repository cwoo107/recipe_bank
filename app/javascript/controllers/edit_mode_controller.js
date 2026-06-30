import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["editOnlyItems"]
    static values  = { editing: { type: Boolean, default: false } }

    toggle() {
        this.editingValue = !this.editingValue
    }

    editingValueChanged() {
        this.editOnlyItemsTargets.forEach(el => {
            el.classList.toggle("hidden", !this.editingValue)
        })
    }

    // Fires whenever a new editOnlyItems target is inserted into the DOM,
    // including via Turbo Stream — keeps it in sync with current edit state.
    editOnlyItemsTargetConnected(element) {
        element.classList.toggle("hidden", !this.editingValue)
    }
}