import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["input", "nav"]
    static values  = { selected: String, weekStart: String }

    connect() {
        if (!this.weekStartValue) {
            const base = this.selectedValue
                ? new Date(this.selectedValue + "T00:00:00")
                : new Date()
            this.weekStartValue = this.getMonday(base)
        }
        this.render()
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
        if (this.hasInputTarget) this.inputTarget.value = date
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

            return `
            <button type="button"
                    data-action="click->week-date-picker#selectDate"
                    data-date="${dateStr}"
                    class="relative inline-flex flex-col items-center flex-1 px-1 py-2 text-xs focus:z-20 focus:outline-offset-0 transition-colors
                      ${isSelected
                ? "z-10 bg-[#5f734c] text-white dark:bg-[#7a8f62]"
                : "text-gray-900 inset-ring inset-ring-gray-300 hover:bg-gray-50 dark:text-gray-200 dark:inset-ring-white/10 dark:hover:bg-white/5"
            }">
              <span class="font-semibold text-sm">${d.getDate()}</span>
              <span class="text-xs opacity-75">${dayNames[d.getDay()]}</span>
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

    getMonday(date) {
        const d = new Date(date)
        const day = d.getDay()
        const diff = (day === 0) ? -6 : 1 - day
        d.setDate(d.getDate() + diff)
        return this.formatDate(d)
    }

    formatDate(d) {
        const y = d.getFullYear()
        const m = String(d.getMonth() + 1).padStart(2, "0")
        const day = String(d.getDate()).padStart(2, "0")
        return `${y}-${m}-${day}`
    }
}