import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "nav"]
    // recurrence (optional): the rule a recurring meal's start date begins —
    // { type: "interval", interval: 2 } or { type: "days_of_week", days: [1, 3] },
    // plus end: "YYYY-MM-DD" or endOfWeek: true. Every later date the rule
    // lands on gets a lighter highlight (see #occursOn). Set by the
    // recurrence-pattern controller as the form changes.
    static values  = { selected: String, weekStart: String, firstDay: { type: Number, default: 1 }, recurrence: Object }

    connect() {
        if (!this.weekStartValue) {
            const base = this.selectedValue
                ? new Date(this.selectedValue + "T00:00:00")
                : new Date()
            this.weekStartValue = this.getWeekStart(base)
        }
        this.render()
    }

    recurrenceValueChanged() {
        if (this.weekStartValue && this.hasNavTarget) this.render()
    }

    prevWeek() {
        const d = new Date(this.weekStartValue + "T00:00:00")
        d.setDate(d.getDate() - 7)
        this.weekStartValue = this.formatDate(d)
        this.render()
    }

    nextWeek() {
        const d = new Date(this.weekStartValue + "T00:00:00")
        d.setDate(d.getDate() + 7)
        this.weekStartValue = this.formatDate(d)
        this.render()
    }

    selectDate(event) {
        const date = event.currentTarget.dataset.date
        this.selectedValue = date
        if (this.hasInputTarget) {
            this.inputTarget.value = date
            this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
        }
        this.render()
    }

    render() {
        const weekStart = new Date(this.weekStartValue + "T00:00:00")
        const days = []
        for (let i = 0; i < 7; i++) {
            const d = new Date(weekStart)
            d.setDate(d.getDate() + i)
            days.push(d)
        }

        const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        this.navTarget.innerHTML = `
      <nav class="isolate inline-flex -space-x-px rounded-md shadow-xs dark:shadow-none w-full">
        <button type="button"
                data-action="click->week-date-picker#prevWeek"
                class="relative inline-flex items-center rounded-l-md px-2 py-2 text-gray-400 inset-ring inset-ring-gray-300 hover:bg-gray-50 focus:z-20 focus:outline-offset-0 dark:inset-ring-white/10 dark:hover:bg-white/5">
          <span class="sr-only">Previous week</span>
          <svg viewBox="0 0 20 20" fill="currentColor" class="size-5">
            <path fill-rule="evenodd" clip-rule="evenodd" d="M11.78 5.22a.75.75 0 0 1 0 1.06L8.06 10l3.72 3.72a.75.75 0 1 1-1.06 1.06l-4.25-4.25a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Z"/>
          </svg>
        </button>

        ${days.map((d, i) => {
            const dateStr = this.formatDate(d)
            const isSelected = dateStr === this.selectedValue
            const repeats = !isSelected && this.occursOn(d)

            return `
            <button type="button"
                    data-action="click->week-date-picker#selectDate"
                    data-date="${dateStr}"
                    ${repeats ? "data-repeats" : ""}
                    aria-pressed="${isSelected}"
                    class="relative inline-flex flex-col items-center flex-1 px-1 py-2 text-xs focus:z-20 focus:outline-offset-0 transition-colors
                      ${isSelected
                ? "z-10 bg-[#5f734c] text-white dark:bg-[#7a8f62]"
                : repeats
                ? "bg-[#5f734c]/25 text-[#3f4b33] inset-ring inset-ring-[#5f734c]/50 hover:bg-[#5f734c]/35 dark:bg-[#7a8f62]/30 dark:text-white dark:inset-ring-[#7a8f62]/40 dark:hover:bg-[#7a8f62]/35"
                : "text-gray-900 inset-ring inset-ring-gray-300 hover:bg-gray-50 dark:text-gray-200 dark:inset-ring-white/10 dark:hover:bg-white/5"
            }">
              <span class="font-semibold text-sm">${d.getDate()}</span>
              <span class="text-xs opacity-75">${dayNames[d.getDay()]}</span>
              ${repeats ? `<span class="sr-only">(repeats)</span>` : ""}
            </button>
          `
        }).join("")}

        <button type="button"
                data-action="click->week-date-picker#nextWeek"
                class="relative inline-flex items-center rounded-r-md px-2 py-2 text-gray-400 inset-ring inset-ring-gray-300 hover:bg-gray-50 focus:z-20 focus:outline-offset-0 dark:inset-ring-white/10 dark:hover:bg-white/5">
          <span class="sr-only">Next week</span>
          <svg viewBox="0 0 20 20" fill="currentColor" class="size-5">
            <path fill-rule="evenodd" clip-rule="evenodd" d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z"/>
          </svg>
        </button>
      </nav>
    `
    }

    // Whether the recurrence lands on `date` — RecurringMeal#occurs_on?, with
    // the selected date as the start date.
    occursOn(date) {
        const rule = this.recurrenceValue
        if (!rule.type || !this.selectedValue) return false

        const dateStr = this.formatDate(date)
        if (dateStr < this.selectedValue) return false
        const end = rule.endOfWeek ? this.endOfWeek(this.selectedValue) : rule.end
        if (end && dateStr > end) return false

        if (rule.type === "interval") {
            const interval = Number(rule.interval)
            return interval > 0 && this.daysBetween(this.selectedValue, dateStr) % interval === 0
        }
        if (rule.type === "days_of_week") return (rule.days || []).includes(date.getDay())
        return false
    }

    // Last day of the week containing the YYYY-MM-DD `dateStr`.
    endOfWeek(dateStr) {
        const d = new Date(this.getWeekStart(new Date(dateStr + "T00:00:00")) + "T00:00:00")
        d.setDate(d.getDate() + 6)
        return this.formatDate(d)
    }

    // Whole days from one YYYY-MM-DD to another (in UTC, so a clock change
    // doesn't leave a 23-hour day).
    daysBetween(from, to) {
        return Math.round((Date.parse(to + "T00:00:00Z") - Date.parse(from + "T00:00:00Z")) / 86400000)
    }

    // Start of the week containing `date`, using the household's week start
    // day (firstDayValue, 0 = Sunday).
    getWeekStart(date) {
        const d = new Date(date)
        d.setDate(d.getDate() - ((d.getDay() - this.firstDayValue + 7) % 7))
        return this.formatDate(d)
    }

    formatDate(d) {
        const y = d.getFullYear()
        const m = String(d.getMonth() + 1).padStart(2, "0")
        const day = String(d.getDate()).padStart(2, "0")
        return `${y}-${m}-${day}`
    }
}