import { Controller } from "@hotwired/stimulus"

// Household settings: time for to-dos is set per week or per day — show
// just the field for whichever is picked.
export default class extends Controller {
    static targets = ["period", "week", "day"]

    connect() {
        this.toggle()
    }

    toggle() {
        const perDay = this.periodTarget.value === "day"
        this.weekTarget.hidden = perDay
        this.dayTarget.hidden = !perDay
    }
}
