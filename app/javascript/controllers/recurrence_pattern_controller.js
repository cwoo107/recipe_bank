import { Controller } from "@hotwired/stimulus"

// Toggles the sub-fields inside a shared/_recurrence_fields.html.erb block:
// interval-days vs specific-weekdays, and the custom end-date input. Also
// keeps the start date picker (week-date-picker) showing every date the
// rule will put the meal on.
export default class extends Controller {
    static targets = ["intervalFields", "weekdayFields", "endDateField", "startPicker"]

    connect() {
        this.syncPreview()
    }

    // On any change in the block (it's on the wrapper, so it runs after the
    // handlers below).
    syncPreview() {
        if (!this.hasStartPickerTarget) return

        const checked = (name) => this.element.querySelector(`input[name$="[${name}]"]:checked`)?.value
        const type = checked("pattern_type")
        const endType = checked("end_type")
        const rule = { type, endOfWeek: endType === "week" }
        if (type === "interval") rule.interval = Number(checked("interval_days"))
        if (type === "days_of_week") {
            rule.days = [...this.element.querySelectorAll('input[name$="[days_of_week][]"]:checked')].map((box) => Number(box.value))
        }
        if (endType === "date") rule.end = this.element.querySelector('input[name$="[end_date]"]')?.value || null

        this.startPickerTarget.dataset.weekDatePickerRecurrenceValue = JSON.stringify(rule)
    }

    patternTypeChanged(event) {
        const isWeekdayPattern = event.target.value === "days_of_week"
        this.intervalFieldsTarget.classList.toggle("hidden", isWeekdayPattern)
        this.weekdayFieldsTarget.classList.toggle("hidden", !isWeekdayPattern)
    }

    endTypeChanged(event) {
        this.endDateFieldTarget.classList.toggle("hidden", event.target.value !== "date")
    }
}
