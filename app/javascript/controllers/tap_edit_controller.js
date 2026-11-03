// app/javascript/controllers/tap_edit_controller.js
//
// Clicking or tapping a card opens its edit dialog. Used by the to-do,
// restock and weekly chore cards: the card carries data-controller="tap-edit"
// and data-action="click->tap-edit#open", and the screen-reader-only button
// that opens its edit dialog is the "edit" target (keyboard users tab to it;
// the card shows a focus ring). Cards without one (someone who can't edit
// it) do nothing on click. A drag doesn't count — the browser sends no click
// after one.
//
// Clicks on the card's own controls (checkbox, Stocked / Restock, a task,
// the dialog itself) are left alone.

import { Controller } from "@hotwired/stimulus"

const CONTROLS = "a, button, input, select, textarea, label, form, dialog, [role=button]"

export default class extends Controller {
    static targets = ["edit"]

    open(event) {
        if (!this.hasEditTarget) return
        if (event.target.closest(CONTROLS)) return

        this.editTarget.click()
    }
}
