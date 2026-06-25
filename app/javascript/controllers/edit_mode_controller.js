import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["editButton", "editOnlyItems"]
    static values  = { editing: { type: Boolean, default: false } }

    toggle() {
        this.editingValue = !this.editingValue
    }

    editingValueChanged() {
        // Update button appearance
        if (this.hasEditButtonTarget) {
            if (this.editingValue) {
                this.editButtonTarget.classList.add("bg-[#5f734c]", "text-white", "inset-ring-[#5f734c]")
                this.editButtonTarget.classList.remove("bg-white", "text-gray-900", "inset-ring-gray-300",
                    "dark:bg-white/10", "dark:text-white", "dark:inset-ring-white/5")
            } else {
                this.editButtonTarget.classList.remove("bg-[#5f734c]", "text-white", "inset-ring-[#5f734c]")
                this.editButtonTarget.classList.add("bg-white", "text-gray-900", "inset-ring-gray-300",
                    "dark:bg-white/10", "dark:text-white", "dark:inset-ring-white/5")
            }
        }

        // Show/hide all edit-only elements
        this.editOnlyItemsTargets.forEach(el => {
            el.classList.toggle("hidden", !this.editingValue)
        })
    }
}