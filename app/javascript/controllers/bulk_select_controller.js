import { Controller } from "@hotwired/stimulus"

// Row checkboxes with a select-all box in the header, and a bar of actions
// (its count, its delete button) that shows once anything is ticked. The
// Chore Chart's Table View (chores/_table).
export default class extends Controller {
    static targets = ["all", "item", "bar", "count"]

    connect() {
        this.refresh()
    }

    // A row re-rendered by an inline edit comes back unticked — recount.
    itemTargetConnected() {
        this.refresh()
    }

    itemTargetDisconnected() {
        this.refresh()
    }

    toggleAll() {
        this.itemTargets.forEach(item => { item.checked = this.allTarget.checked })
        this.refresh()
    }

    refresh() {
        const total    = this.itemTargets.length
        const selected = this.itemTargets.filter(item => item.checked).length

        if (this.hasAllTarget) {
            this.allTarget.checked = total > 0 && selected === total
            this.allTarget.indeterminate = selected > 0 && selected < total
        }
        if (this.hasBarTarget) this.barTarget.hidden = selected === 0
        if (this.hasCountTarget) this.countTarget.textContent = `${selected} ${selected === 1 ? "chore" : "chores"} selected`
    }
}
