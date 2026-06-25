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
}