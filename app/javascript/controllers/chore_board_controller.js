// app/javascript/controllers/chore_board_controller.js
//
// Wraps SortableJS for the weekly chore board: a row per chore category, a
// cell per day within it. Every cell shares a group with the "Coming up"
// list so a due chore can be dropped straight onto a day. Mirrors
// kanban_controller.js's cross-column pattern. Desktop only — the mobile
// accordion layout doesn't support drag.
//
// Dragging a board card back up into "Coming up" takes it off this week
// (for a weekly/biweekly chore, after asking whether that's just this week
// or every week from here on — weekly_chores/_remove_dialog).
//
// Two confirmations can come up on a drop (both app-styled <dialog>s, see
// weekly_chores/_category_change_dialog and _move_dialog):
//   - dropping into a different category's row asks before re-filing the
//     chore under that category;
//   - moving a weekly/biweekly chore to a different day asks whether the
//     new day applies going forward or just this week.
// Cancelling either puts the card back where it came from.
//
// The category rows themselves are also sortable, dragged by their heading.

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Only ".chore-card" elements count as sortable items — this keeps any
// other markup out of SortableJS's index math, so a drop always lands among
// the actual cards (not above/below them).
const DRAGGABLE_SELECTOR = ".chore-card"

export default class extends Controller {
    static targets = [
        "dueList", "column", "rows",
        "moveDialog", "moveDay", "moveDayAgain", "moveChoreName",
        "categoryDialog", "categoryChoreName", "categoryFrom", "categoryTo", "categoryToAgain",
        "removeDialog", "removeChoreName", "removeFrequency"
    ]
    static values = {
        weekStart: String,
        createUrl: String,
        reorderUrl: String,
        categoryReorderUrl: String
    }

    connect() {
        this.sortables = []

        if (this.hasDueListTarget) {
            // A due chore hasn't been added to this week yet — dropping it onto
            // a cell clones it in place (the recommendation stays put until
            // the create request removes it) rather than reordering it. A
            // board card dropped back in here comes off this week.
            this.sortables.push(Sortable.create(this.dueListTarget, {
                group: {
                    name: "chore-board",
                    pull: "clone",
                    put: (_to, _from, dragEl) => Boolean(dragEl.dataset.weeklyChoreId)
                },
                handle: ".sortable-handle",
                draggable: DRAGGABLE_SELECTOR,
                sort: false,
                animation: 150,
                onAdd: this.unschedule.bind(this)
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

        if (this.hasRowsTarget && this.categoryReorderUrlValue) {
            this.sortables.push(Sortable.create(this.rowsTarget, {
                group: "category-rows",
                handle: ".category-row-handle",
                draggable: "[data-category-row-id]",
                animation: 150,
                onEnd: this.reorderRows.bind(this)
            }))
        }
    }

    disconnect() {
        this.#settle(null)
        this.sortables.forEach((sortable) => sortable.destroy())
    }

    async add(event) {
        const to = event.to
        const scheduledDate = to.dataset.date || ""
        const position = event.newIndex + 1

        // In clone mode, SortableJS's evt.item does not reliably reference the
        // clone that actually landed in the target cell — read the real
        // draggable child at the drop index instead of trusting evt.item.
        const item = to.querySelectorAll(DRAGGABLE_SELECTOR)[event.newIndex] || event.item
        if (!item) return

        const categoryChanged = item.dataset.categoryKey !== to.dataset.categoryKey
        if (categoryChanged && this.hasCategoryDialogTarget) {
            const answer = await this.askCategoryChange(item, to)
            if (answer !== "change") {
                this.#revert(event, item)
                return
            }
        }

        const body = { scheduled_date: scheduledDate, position }
        if (categoryChanged) body.category_key = to.dataset.categoryKey

        if (item.dataset.weeklyChoreId) {
            body.scope = "forward"
            const dayChanged = (event.from.dataset.date || "") !== scheduledDate
            if (dayChanged && item.dataset.recurring === "true" && this.hasMoveDialogTarget) {
                body.scope = await this.askMoveScope(item.dataset.choreName, scheduledDate)
                if (!body.scope) {
                    this.#revert(event, item)
                    return
                }
            }

            fetch(`/weekly_chores/${item.dataset.weeklyChoreId}/move`, {
                method: "POST",
                headers: this.#headers(),
                body: JSON.stringify(body)
            }).then((response) => {
                if (response.ok && categoryChanged) item.dataset.categoryKey = to.dataset.categoryKey
                this.#persistOrder(to)
            })
            return
        }

        const choreId = item.dataset.choreId
        if (!choreId) return

        // Counter-intuitively, `item` here (found in the target cell) is
        // SortableJS's REAL dragged node — it keeps the original due_chore_N
        // id. The stand-in it leaves behind in the due list (to visually fill
        // the gap) is a separate node with its id stripped, so it must be
        // found by data-chore-id, not by the (now relocated) id. Removing it
        // immediately — rather than waiting on the server round trip — is
        // also what stops the same due chore from being dropped a second
        // time: a chore can only be on a week's list once, so every drop
        // after the first would otherwise silently fail.
        const leftover = this.#dueLeftover(choreId, item)
        if (leftover) leftover.remove()

        // Give the dragged node a predictable id so the turbo_stream response
        // can replace it once the real WeeklyChore exists.
        item.id = `pending_weekly_chore_${choreId}`
        item.classList.add("opacity-50")

        fetch(this.createUrlValue, {
            method: "POST",
            headers: { ...this.#headers(), "Accept": "text/vnd.turbo-stream.html" },
            body: JSON.stringify({
                ...body,
                chore_id: choreId,
                week_start: this.weekStartValue,
                source: "drag"
            })
        })
            .then((response) => response.text())
            .then((html) => window.Turbo.renderStreamMessage(html))
            .catch(() => { item.remove() })
    }

    reorder(event) {
        this.#persistOrder(event.to)
    }

    // A board card dragged back into "Coming up": take it off this week. A
    // weekly/biweekly chore first asks whether that's just this week or
    // every week from here on. The turbo_stream response removes the card
    // (both desktop and mobile copies) and, when the chore is still coming
    // due, adds its "Coming up" card in its place.
    async unschedule(event) {
        const item = event.item
        const id = item.dataset.weeklyChoreId
        if (!id) return

        let scope = "all"
        if (item.dataset.recurring === "true" && this.hasRemoveDialogTarget) {
            if (this.hasRemoveChoreNameTarget) this.removeChoreNameTarget.textContent = item.dataset.choreName || "This chore"
            if (this.hasRemoveFrequencyTarget) this.removeFrequencyTarget.textContent = item.dataset.frequencyLabel || ""
            scope = await this.#ask(this.removeDialogTarget)
            if (!scope) {
                this.#revert(event, item)
                return
            }
        }

        item.classList.add("opacity-50")

        fetch(`/weekly_chores/${id}?scope=${scope}`, {
            method: "DELETE",
            headers: { ...this.#headers(), "Accept": "text/vnd.turbo-stream.html" }
        })
            .then((response) => {
                if (!response.ok) throw new Error(response.statusText)
                return response.text()
            })
            .then((html) => window.Turbo.renderStreamMessage(html))
            .catch(() => {
                item.classList.remove("opacity-50")
                this.#revert(event, item)
            })
    }

    reorderRows(event) {
        if (event.oldIndex === event.newIndex) return

        const order = Array.from(this.rowsTarget.querySelectorAll("[data-category-row-id]"))
            .map((row) => row.dataset.categoryRowId)

        fetch(this.categoryReorderUrlValue, {
            method: "POST",
            headers: this.#headers(),
            body: JSON.stringify({ order })
        })
    }

    // Resolves to "change" or null (cancelled).
    askCategoryChange(item, to) {
        const choreName = item.dataset.choreName || item.querySelector("p")?.textContent?.trim()
        const toName = to.dataset.categoryName || "this category"

        if (this.hasCategoryChoreNameTarget) this.categoryChoreNameTarget.textContent = choreName || "This chore"
        if (this.hasCategoryFromTarget) this.categoryFromTarget.textContent = this.#categoryName(item.dataset.categoryKey)
        this.categoryToTargets.concat(this.categoryToAgainTargets).forEach((el) => { el.textContent = toName })

        return this.#ask(this.categoryDialogTarget)
    }

    // Resolves to "forward", "week", or null (cancelled).
    askMoveScope(choreName, isoDate) {
        const [year, month, day] = isoDate.split("-").map(Number)
        const dayName = new Date(year, month - 1, day).toLocaleDateString(undefined, { weekday: "long" })
        this.moveDayTargets.concat(this.moveDayAgainTargets).forEach((el) => { el.textContent = dayName })
        if (this.hasMoveChoreNameTarget) this.moveChoreNameTarget.textContent = choreName || "This chore"

        return this.#ask(this.moveDialogTarget)
    }

    // A dialog button with data-value="…".
    answer(event) {
        this.#settle(event.currentTarget.dataset.value)
    }

    // Cancel button, or the dialog's native "cancel" event (Escape key).
    dismiss(event) {
        event.preventDefault()
        this.#settle(null)
    }

    // A click that lands on the <dialog> itself (not its content) is a
    // click on the ::backdrop.
    dialogBackdrop(event) {
        if (event.target === event.currentTarget) this.#settle(null)
    }

    #ask(dialog) {
        this.#settle(null)
        return new Promise((resolve) => {
            this.pending = { dialog, resolve }
            dialog.showModal()
        })
    }

    #settle(value) {
        const pending = this.pending
        this.pending = null
        if (!pending) return
        if (pending.dialog.open) pending.dialog.close()
        pending.resolve(value)
    }

    #categoryName(key) {
        const cell = this.columnTargets.find((column) => column.dataset.categoryKey === key)
        return cell?.dataset.categoryName || "Uncategorized"
    }

    #dueLeftover(choreId, item) {
        if (!this.hasDueListTarget) return null
        const leftover = this.dueListTarget.querySelector(`[data-chore-id="${choreId}"]`)
        return leftover && leftover !== item ? leftover : null
    }

    // Puts a card back where it was dragged from. A "Coming up" card swaps
    // back in for the stand-in SortableJS left in the due list.
    #revert(event, item) {
        const leftover = item.dataset.choreId && this.#dueLeftover(item.dataset.choreId, item)
        if (leftover) {
            leftover.replaceWith(item)
            return
        }

        const siblings = Array.from(event.from.querySelectorAll(DRAGGABLE_SELECTOR)).filter((el) => el !== item)
        event.from.insertBefore(item, siblings[event.oldIndex] || null)
    }

    #persistOrder(column) {
        const scheduledDate = column.dataset.date || ""
        const order = Array.from(column.querySelectorAll("[data-weekly-chore-id]"))
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
