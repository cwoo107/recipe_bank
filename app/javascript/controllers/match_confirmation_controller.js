import { Controller } from "@hotwired/stimulus"

// Bulk toggles for the import's ingredient-match confirmation list, plus a
// running count of how many ingredients the current ticks would create.
export default class extends Controller {
    static targets = ["checkbox", "summary"]

    connect() {
        this.newIngredientBaseline = Number(this.element.dataset.newIngredientCount || 0)
        this.element.addEventListener("change", () => this.updateSummary())
        this.updateSummary()
    }

    checkAll() {
        this.checkboxTargets.forEach(box => { box.checked = true })
        this.updateSummary()
    }

    uncheckAll() {
        this.checkboxTargets.forEach(box => { box.checked = false })
        this.updateSummary()
    }

    updateSummary() {
        if (!this.hasSummaryTarget) return

        const unticked = this.checkboxTargets.filter(box => !box.checked).length
        const total = this.newIngredientBaseline + unticked

        this.summaryTarget.textContent = total === 0
            ? "No new ingredients will be created."
            : `${total} new ${total === 1 ? "ingredient" : "ingredients"} will be created.`
    }
}
