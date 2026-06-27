// app/javascript/controllers/calendar_controller.js
// Handles click-to-open event modal, keyboard navigation, and
// smooth-scrolls the week/day grid to business hours on load.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.scrollToNow()
    }

    // Scroll the timed grid so that 8 AM is near the top.
    scrollToNow() {
        const grid = this.element.querySelector("[data-calendar-scroll]")
        if (!grid) return
        const pct   = (8 * 60) / (24 * 60)          // 8 AM as fraction
        const top   = pct * grid.scrollHeight
        grid.scrollTop = Math.max(0, top - 48)        // 48px padding
    }
}