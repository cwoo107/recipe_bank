// app/javascript/controllers/tap_edit_controller.js
//
// On a phone, tapping a card opens its edit dialog — the hover-revealed
// edit icon never shows on a touch screen. Used by the to-do, restock and
// weekly chore cards: the card carries data-controller="tap-edit" and
// data-action="click->tap-edit#open", and the button that opens its edit
// dialog is the "edit" target. Cards without one (someone who can't edit
// it) do nothing on tap. From Tailwind's sm breakpoint up the card keeps
// its desktop behavior: drag it, or hover for the edit icon.
//
// Taps on the card's own controls (checkbox, Stocked / Restock, a task,
// the dialog itself) are left alone.

import { Controller } from "@hotwired/stimulus"

const PHONE = window.matchMedia("(max-width: 639px)")
const CONTROLS = "a, button, input, select, textarea, label, form, dialog, [role=button]"

export default class extends Controller {
    static targets = ["edit"]

    open(event) {
        if (!PHONE.matches || !this.hasEditTarget) return
        if (event.target.closest(CONTROLS)) return

        this.editTarget.click()
    }
}
