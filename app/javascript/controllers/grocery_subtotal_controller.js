// app/javascript/controllers/grocery_subtotal_controller.js
//
// The grocery list's Subtotal, kept live. Each row carries its unit price
// (data-price) and quantity; the total is re-added whenever a row comes or
// goes — a quantity change re-renders its row, a delete removes it, and
// items added by anyone in the household are broadcast in — and straight
// away while a quantity is being changed, before the server answers. Only
// the rows on the page count, so a family filter totals what it shows.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["row", "total", "count"]

    rowTargetConnected()    { this.recalculate() }
    rowTargetDisconnected() { this.recalculate() }

    recalculate() {
        let total = 0
        this.rowTargets.forEach((row) => {
            const input = row.querySelector("input[name='grocery_list[units]']")
            const units = parseInt(input?.value ?? row.dataset.units, 10) || 0
            total += (parseFloat(row.dataset.price) || 0) * units
        })

        if (this.hasTotalTarget) this.totalTarget.textContent = `$${total.toFixed(2)}`
        if (this.hasCountTarget) {
            const count = this.rowTargets.length
            this.countTarget.textContent = `${count} item${count === 1 ? "" : "s"}`
        }
    }
}
