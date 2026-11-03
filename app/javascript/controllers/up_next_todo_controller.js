// app/javascript/controllers/up_next_todo_controller.js
//
// A to-do card in the dashboard's Up next (dashboard/_todo_card). Ticking
// its checkbox fades the card out, then marks the to-do done — the form
// posts to TodosController#move, whose response removes the card and fades
// in the next to-do. If saving fails, the card comes back unticked.

import { Controller } from "@hotwired/stimulus"

// Matches the card's duration-300.
const FADE_MS = 300

export default class extends Controller {
    static targets = ["form", "checkbox"]

    complete() {
        this.checkboxTarget.disabled = true
        this.element.classList.add("opacity-0")
        setTimeout(() => this.formTarget.requestSubmit(), FADE_MS)
    }

    restore(event) {
        if (event.detail.success) return

        this.element.classList.remove("opacity-0")
        this.checkboxTarget.checked = false
        this.checkboxTarget.disabled = false
    }
}
