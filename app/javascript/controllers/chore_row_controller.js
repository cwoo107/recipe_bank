import { Controller } from "@hotwired/stimulus"

// Manage Chores editor: the Day field only applies to weekly/biweekly
// chores (Chore::RECURRING_FREQUENCIES). In the mobile modal it hides for
// anything else; in the desktop table the Day cell swaps to a "—"
// placeholder (dayNone) instead.
const RECURRING = ["weekly", "biweekly"]

export default class extends Controller {
    static targets = ["frequency", "day", "dayNone"]

    toggleDay() {
        const recurring = RECURRING.includes(this.frequencyTarget.value)
        this.dayTargets.forEach((el) => el.classList.toggle("hidden", !recurring))
        this.dayNoneTargets.forEach((el) => el.classList.toggle("hidden", recurring))
    }
}
