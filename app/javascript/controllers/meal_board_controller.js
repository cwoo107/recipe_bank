// app/javascript/controllers/meal_board_controller.js
//
// Wraps SortableJS for the meals board: every desktop grid cell (one per day
// and meal type) and the Snacks / Desserts sections share a group, so a meal
// can be dragged to another day, another meal type, or both. Mirrors
// chore_board_controller.js's cross-column pattern. The mobile accordion
// layout doesn't support drag (its Snacks / Desserts sections do).
//
// Each list carries data-meal-name ("Breakfast" … "Dessert") and, for a day
// cell, data-date. Meals have no position, so dropping within the same list
// does nothing. The turbo_stream response (meals/move) re-renders the card
// in its new meal type's colors and moves its mobile copy to match.
//
// A meal a recurring rule generated first asks (meals/_move_dialog) whether
// to move just this one — which detaches it from the rule — or this one and
// every later one, which reshapes the rule (RecurringMeal#move_sequence!).
// Snacks and desserts can't recur, so dropping into those sections never
// asks. Cancelling puts the card back where it came from.
//
// While a drag is in progress the controller element carries
// data-meal-dragging — the board's add buttons hide and empty cells grow to
// fill their slot so they're easy to drop into (see meals/index).

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Only meal cards count as sortable items — keeps the empty-state message
// out of SortableJS's index math.
const DRAGGABLE_SELECTOR = ".meal-card"

export default class extends Controller {
    static targets = ["list", "moveDialog", "moveMealName", "moveSlot"]

    connect() {
        this.sortables = this.listTargets.map((list) => Sortable.create(list, {
            group: "meal-board",
            draggable: DRAGGABLE_SELECTOR,
            // The Edit / Remove buttons (and their dialog) stay clickable.
            filter: "button, form, dialog",
            preventOnFilter: false,
            // On touch screens a quick swipe still scrolls the page.
            delay: 200,
            delayOnTouchOnly: true,
            sort: false,
            animation: 150,
            onStart: () => { this.element.dataset.mealDragging = "" },
            onEnd: () => { delete this.element.dataset.mealDragging },
            onAdd: this.move.bind(this)
        }))
    }

    disconnect() {
        this.#settle(null)
        delete this.element.dataset.mealDragging
        this.sortables.forEach((sortable) => sortable.destroy())
    }

    async move(event) {
        const item = event.item
        const to   = event.to
        const id   = item.dataset.mealId
        if (!id) return

        let scope = "one"
        if (item.dataset.recurring === "true" && to.dataset.date && this.hasMoveDialogTarget) {
            scope = await this.askMoveScope(item, to)
            if (!scope) {
                this.#revert(event, item)
                return
            }
        }

        item.classList.add("opacity-50")

        fetch(`/meals/${id}/move`, {
            method:  "POST",
            headers: { ...this.#headers(), "Accept": "text/vnd.turbo-stream.html" },
            body:    JSON.stringify({ meal_name: to.dataset.mealName, date: to.dataset.date || "", scope })
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

    // Resolves to "one", "sequence", or null (cancelled).
    askMoveScope(item, to) {
        const [year, month, day] = to.dataset.date.split("-").map(Number)
        const dayName = new Date(year, month - 1, day).toLocaleDateString(undefined, { weekday: "long" })

        if (this.hasMoveMealNameTarget) this.moveMealNameTarget.textContent = item.dataset.mealTitle || "This meal"
        if (this.hasMoveSlotTarget) this.moveSlotTarget.textContent = `${dayName} ${to.dataset.mealName.toLowerCase()}`

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

    // Puts a card back where it was dragged from.
    #revert(event, item) {
        const siblings = Array.from(event.from.querySelectorAll(DRAGGABLE_SELECTOR)).filter((el) => el !== item)
        event.from.insertBefore(item, siblings[event.oldIndex] || null)
    }

    #headers() {
        const token = document.querySelector("meta[name='csrf-token']")?.content
        return {
            "Content-Type": "application/json",
            ...(token ? { "X-CSRF-Token": token } : {})
        }
    }
}
