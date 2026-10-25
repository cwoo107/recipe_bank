import { Controller } from "@hotwired/stimulus"

// The grocery list's "Select all" and "Delete all checked items" buttons:
// the delete button shows only while something's ticked off, and "Select
// all" becomes "Unselect all" once everything is. Rows are re-rendered by
// the server each time one's ticked, so it recounts as they come and go.
export default class extends Controller {
    static targets = ["box", "deleteButton", "selectAll", "unselectAll"]

    connect() {
        this.refresh()
    }

    boxTargetConnected() {
        this.refresh()
    }

    boxTargetDisconnected() {
        this.refresh()
    }

    refresh() {
        const total   = this.boxTargets.length
        const checked = this.boxTargets.filter(box => box.checked).length
        const all     = total > 0 && checked === total

        if (this.hasDeleteButtonTarget) this.deleteButtonTarget.hidden = checked === 0
        if (this.hasSelectAllTarget) this.selectAllTarget.hidden = total === 0 || all
        if (this.hasUnselectAllTarget) this.unselectAllTarget.hidden = !all
    }
}
