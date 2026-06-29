// app/javascript/controllers/event_stack_controller.js
// Brings an overlapping event chip to the top on hover, drops it back on leave.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    lift() {
        this.element.style.zIndex = 50
    }

    drop() {
        this.element.style.zIndex = null
    }
}