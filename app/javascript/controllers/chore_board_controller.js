// app/javascript/controllers/chore_board_controller.js
//
// Wraps SortableJS for the weekly chore board: one column per day (Mon..Sun),
// sharing a group with the "Due soon" list so a due chore can be dropped
// straight onto a day. Mirrors kanban_controller.js's cross-column pattern.
// Desktop only — the mobile accordion layout doesn't support drag.

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Only ".chore-card" elements count as sortable items — this keeps day
// headers out of SortableJS's index math, so a drop always lands among the
// actual cards (not above/below them).
const DRAGGABLE_SELECTOR = ".chore-card"

export default class extends Controller {
    static targets = ["dueList", "column"]
    static values = {
        weekStart: String,
        createUrl: String,
        reorderUrl: String
    }

    connect() {
        this.sortables = []

        if (this.hasDueListTarget) {
            // A due chore hasn't been added to this week yet — dropping it onto
            // a column clones it in place (the recommendation stays put until
            // the create request removes it) rather than reordering it.
            this.sortables.push(Sortable.create(this.dueListTarget, {
                group: { name: "chore-board", pull: "clone", put: false },
                handle: ".sortable-handle",
                draggable: DRAGGABLE_SELECTOR,
                sort: false,
                animation: 150
            }))
        }

        this.columnTargets.forEach((column) => {
            this.sortables.push(Sortable.create(column, {
                group: "chore-board",
                handle: ".sortable-handle",
                draggable: DRAGGABLE_SELECTOR,
                animation: 150,
                onAdd: this.add.bind(this),
                onUpdate: this.reorder.bind(this)
            }))
        })
    }

    disconnect() {
        this.sortables.forEach((sortable) => sortable.destroy())
    }

    add(event) {
        const scheduledDate = event.to.dataset.date || ""
        const position = event.newIndex + 1

        // In clone mode, SortableJS's evt.item does not reliably reference the
        // clone that actually landed in the target column — read the real
        // draggable child at the drop index instead of trusting evt.item.
        const item = event.to.querySelectorAll(DRAGGABLE_SELECTOR)[event.newIndex] || event.item
        if (!item) return

        if (item.dataset.weeklyChoreId) {
            fetch(`/weekly_chores/${item.dataset.weeklyChoreId}/move`, {
                method: "POST",
                headers: this.#headers(),
                body: JSON.stringify({ scheduled_date: scheduledDate, position })
            })
            return
        }

        const choreId = item.dataset.choreId
        if (!choreId) return

        // Counter-intuitively, `item` here (found in the target column) is
        // SortableJS's REAL dragged node — it keeps the original due_chore_N
        // id. The stand-in it leaves behind in the due list (to visually fill
        // the gap) is a separate node with its id stripped, so it must be
        // found by data-chore-id, not by the (now relocated) id. Removing it
        // immediately — rather than waiting on the server round trip — is
        // also what stops the same due chore from being dropped a second
        // time: a chore can only be on a week's list once, so every drop
        // after the first would otherwise silently fail.
        if (this.hasDueListTarget) {
            const leftover = this.dueListTarget.querySelector(`[data-chore-id="${choreId}"]`)
            if (leftover && leftover !== item) leftover.remove()
        }

        // Give the dragged node a predictable id so the turbo_stream response
        // can replace it once the real WeeklyChore exists.
        item.id = `pending_weekly_chore_${choreId}`
        item.classList.add("opacity-50")

        fetch(this.createUrlValue, {
            method: "POST",
            headers: { ...this.#headers(), "Accept": "text/vnd.turbo-stream.html" },
            body: JSON.stringify({
                chore_id: choreId,
                week_start: this.weekStartValue,
                scheduled_date: scheduledDate,
                position,
                source: "drag"
            })
        })
            .then((response) => response.text())
            .then((html) => window.Turbo.renderStreamMessage(html))
            .catch(() => { item.remove() })
    }

    reorder(event) {
        const scheduledDate = event.to.dataset.date || ""
        const order = Array.from(event.to.querySelectorAll("[data-weekly-chore-id]"))
            .map((el) => el.dataset.weeklyChoreId)

        fetch(this.reorderUrlValue, {
            method: "POST",
            headers: this.#headers(),
            body: JSON.stringify({ scheduled_date: scheduledDate, order })
        })
    }

    #headers() {
        return {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        }
    }
}
