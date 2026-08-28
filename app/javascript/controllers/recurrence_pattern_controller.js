import { Controller } from "@hotwired/stimulus"

// Toggles the sub-fields inside a shared/_recurrence_fields.html.erb block:
// interval-days vs specific-weekdays, and the custom end-date input.
export default class extends Controller {
    static targets = ["intervalFields", "weekdayFields", "endDateField"]

    patternTypeChanged(event) {
        const isWeekdayPattern = event.target.value === "days_of_week"
        this.intervalFieldsTarget.classList.toggle("hidden", isWeekdayPattern)
        this.weekdayFieldsTarget.classList.toggle("hidden", !isWeekdayPattern)
    }

    endTypeChanged(event) {
        this.endDateFieldTarget.classList.toggle("hidden", event.target.value !== "date")
    }
}
