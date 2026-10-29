import { Controller } from "@hotwired/stimulus"
import AirDatepicker from "air-datepicker"
import { autoUpdate, computePosition, flip, offset, shift } from "@floating-ui/dom"
import localeEn from "air-datepicker/locale/en"

// Put on an <input type="date">. On desktop it swaps the browser's own
// calendar for Air Datepicker so it looks the same in every browser; touch
// devices keep the native picker, which phones already do well.
//
// The input stays the visible, focusable field (so its label and any other
// controller's actions on it keep working) but becomes a read-only text box
// showing a friendly date. A hidden input takes over its name and submits
// YYYY-MM-DD, same as the native field did. Picking a date fires `change` on
// the input (Air Datepicker's own, which doesn't bubble), so inline-cell
// (chores/_last_done_cell) saves it like before.
export default class extends Controller {
    static values = { firstDay: { type: Number, default: 0 } }
    static displayFormat = "E, MMM d, yyyy"

    connect() {
        if (window.matchMedia("(pointer: coarse)").matches) return

        const input = this.element
        this.hidden = document.createElement("input")
        this.hidden.type = "hidden"
        this.hidden.name = input.name
        this.hidden.value = input.value
        if (input.hasAttribute("form")) this.hidden.setAttribute("form", input.getAttribute("form"))
        input.after(this.hidden)

        const selected = this.#parse(input.value)
        const minDate = this.#parse(input.min)
        const maxDate = this.#parse(input.max)
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const todayAllowed = (!minDate || today >= minDate) && (!maxDate || today <= maxDate)
        input.removeAttribute("name")
        input.type = "text"
        input.readOnly = true
        input.autocomplete = "off"

        this.picker = new AirDatepicker(input, {
            locale: { ...localeEn, firstDay: this.firstDayValue },
            dateFormat: this.constructor.displayFormat,
            // Air Datepicker writes the alt field before it fires `change` on the
            // input, so whatever saves on that change submits the new date.
            altField: this.hidden,
            altFieldDateFormat: "yyyy-MM-dd",
            selectedDates: selected ? [selected] : [],
            // Open on the selected date's month, not this month.
            startDate: selected || today,
            minDate: minDate || "",
            maxDate: maxDate || "",
            // Not autoClose: that hides (and blurs the input) as soon as a day is
            // clicked, before the new value is written and `change` fires, so a
            // blur-to-save field would save the old date. onSelect runs after
            // `change`, so closing there is safe.
            onSelect: ({ datepicker }) => datepicker.hide(),
            container: input.closest("dialog") || "",
            position: this.#position,
            buttons: [
                ...(todayAllowed ? [{ content: "Today", onClick: (dp) => dp.selectDate(new Date()) }] : []),
                ...(input.required ? [] : ["clear"]),
            ],
        })
        input.value = selected ? this.picker.formatDate(selected, this.constructor.displayFormat) : ""

        // Keep focus on the input while clicking the calendar, so a blur-to-save
        // field doesn't save (and close) before the date is picked. Listens on
        // the document because Air Datepicker only builds its element on first
        // show.
        this.onMousedown = (event) => {
            if (this.picker?.$datepicker?.contains(event.target)) event.preventDefault()
        }
        document.addEventListener("mousedown", this.onMousedown)

        // Enter picks the keyboard-highlighted day before anything else on the
        // input (e.g. inline-cell's save-on-Enter) sees the key.
        this.onKeydown = (event) => {
            if (event.key !== "Enter" || !this.picker.visible || !this.picker.focusDate) return
            event.preventDefault()
            event.stopImmediatePropagation()
            this.picker.selectDate(this.picker.focusDate)
        }
        input.addEventListener("keydown", this.onKeydown, { capture: true })

        // Put the native field back before Turbo snapshots the page, so a
        // restored page reconnects from a clean <input type="date">.
        this.teardown = this.teardown.bind(this)
        document.addEventListener("turbo:before-cache", this.teardown)
    }

    disconnect() {
        this.teardown()
    }

    teardown() {
        if (!this.picker) return
        document.removeEventListener("turbo:before-cache", this.teardown)
        document.removeEventListener("mousedown", this.onMousedown)

        const input = this.element
        input.removeEventListener("keydown", this.onKeydown, { capture: true })
        this.stopPositioning?.()
        this.picker.destroy()
        this.picker = null

        input.type = "date"
        input.readOnly = false
        input.name = this.hidden.name
        input.value = this.hidden.value
        this.hidden.remove()
    }

    // Floating UI instead of Air Datepicker's own positioning: `fixed`, so a
    // dialog's overflow doesn't clip the calendar, and it flips above the field
    // when there's no room below. Air Datepicker calls this on show (and again
    // on month changes, which autoUpdate already covers) and calls what it
    // returns on hide, which must call done() to remove the calendar.
    #position = ({ $datepicker, $target, isViewChange, done }) => {
        if (!isViewChange) {
            $datepicker.style.position = "fixed"
            this.stopPositioning = autoUpdate($target, $datepicker, () => {
                computePosition($target, $datepicker, {
                    strategy: "fixed",
                    placement: "bottom-start",
                    middleware: [offset(6), flip(), shift({ padding: 8 })],
                }).then(({ x, y }) => Object.assign($datepicker.style, { left: `${x}px`, top: `${y}px` }))
            })
        }
        return () => {
            this.stopPositioning?.()
            this.stopPositioning = null
            done()
        }
    }

    // "YYYY-MM-DD" -> local midnight (not UTC, which shows as the day before
    // in US time zones).
    #parse(value) {
        const [year, month, day] = (value || "").split("-").map(Number)
        return year && month && day ? new Date(year, month - 1, day) : null
    }
}
