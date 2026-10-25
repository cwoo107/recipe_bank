import { Controller } from "@hotwired/stimulus"

// The to-dos' time budget: −/+ buttons step the amount (half hours per
// week, or five minutes per day) and the form submits itself once the
// clicking stops, so a run of clicks saves once.
export default class extends Controller {
    static targets = ["input", "label"]
    static values  = { step: Number, min: Number, unit: String }

    disconnect() {
        clearTimeout(this.timeout)
    }

    increment() {
        this.#change(this.stepValue)
    }

    decrement() {
        this.#change(-this.stepValue)
    }

    #change(delta) {
        const current = parseFloat(this.inputTarget.value) || this.minValue
        const next = Math.max(this.minValue, Math.round((current + delta) * 100) / 100)
        if (next === current) return

        this.inputTarget.value = next
        this.labelTarget.textContent = this.#label(next)

        clearTimeout(this.timeout)
        this.timeout = setTimeout(() => this.element.requestSubmit(), 500)
    }

    // "7.5 hours / week", "1 hour / week", or "35 min / day".
    #label(amount) {
        if (this.unitValue !== "hour") return `${amount} ${this.unitValue}`
        return `${amount} ${amount === 1 ? "hour" : "hours"} / week`
    }
}
