import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["count", "quantity"]
    static values  = { base: Number }

    // Opens at what the recipe makes; the +/- buttons scale from there. Also
    // runs when the count is re-rendered after the recipe's servings are
    // edited (recipes/_servings_scaler), which makes that the new base.
    countTargetConnected(element) {
        const wasScaled = this.current && this.current !== this.baseValue
        this.baseValue = parseInt(element.textContent, 10)
        this.current   = this.baseValue
        if (wasScaled) this.update()
    }

    // Back to the recipe's own amounts — on entering edit mode, where the
    // quantities being edited are the recipe's, not a scaled copy.
    reset() {
        if (!this.hasCountTarget || this.current === this.baseValue) return

        this.current = this.baseValue
        this.update()
    }

    // A row re-rendered mid-scale (e.g. after an inline quantity edit) comes
    // back at its base quantity — rescale it so the column stays consistent.
    quantityTargetConnected(element) {
        if (!this.current || this.current === this.baseValue) return

        const base = parseFloat(element.dataset.baseQuantity)
        element.textContent = this.formatQuantity(base * (this.current / this.baseValue))
    }

    increment() {
        this.current += 1
        this.update()
    }

    decrement() {
        if (this.current <= 1) return
        this.current -= 1
        this.update()
    }

    update() {
        this.countTarget.textContent = this.current
        const multiplier = this.current / this.baseValue

        this.quantityTargets.forEach(el => {
            const base = parseFloat(el.dataset.baseQuantity)
            const scaled = base * multiplier
            el.textContent = this.formatQuantity(scaled)
        })
    }

    formatQuantity(n) {
        if (n === Math.floor(n)) return n.toString()
        const rounded = Math.round(n * 8) / 8
        const whole = Math.floor(rounded)
        const frac = rounded - whole

        const fractions = {
            0.125: '⅛', 0.25: '¼', 0.375: '⅜',
            0.5: '½', 0.625: '⅝', 0.75: '¾', 0.875: '⅞'
        }

        const fracStr = fractions[Math.round(frac * 8) / 8] || frac.toFixed(2).replace(/^0/, '')

        if (whole === 0) return fracStr
        if (frac < 0.01) return whole.toString()
        return `${whole} ${fracStr}`
    }
}