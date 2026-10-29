import { Controller } from "@hotwired/stimulus"
import { autoUpdate, computePosition, flip, offset, shift } from "@floating-ui/dom"

// The hover card on a calendar event chip (calendars/_event_tooltip). Goes on
// the chip's wrapper, alongside dialog. Fixed-positioned with Floating UI so
// the month cells' and time grid's overflow don't clip it. Mouse only, after
// a short pause so sweeping across the calendar doesn't flash cards; keyboard
// focus shows it straight away. Clicking (opening the event) hides it.
// Not on touch screens, where a tap opens the event.
export default class extends Controller {
    static targets = ["tooltip"]
    static delay = 350

    show(event) {
        if (event.type === "mouseenter" && !window.matchMedia("(hover: hover)").matches) return
        // Not when focus comes back to the chip as its dialog closes after a click.
        if (event.type === "focusin" && !event.target.matches(":focus-visible")) return

        clearTimeout(this.timer)
        this.timer = setTimeout(() => this.#open(), event.type === "focusin" ? 0 : this.constructor.delay)
    }

    hide() {
        clearTimeout(this.timer)
        this.stopPositioning?.()
        this.stopPositioning = null
        this.tooltipTarget.classList.add("hidden")
    }

    disconnect() {
        this.hide()
    }

    #open() {
        if (this.element.querySelector("dialog[open]")) return

        const reference = this.element.querySelector("[aria-describedby]") || this.element
        const tooltip = this.tooltipTarget
        tooltip.classList.remove("hidden")
        this.stopPositioning = autoUpdate(reference, tooltip, () => {
            computePosition(reference, tooltip, {
                strategy: "fixed",
                placement: "top-start",
                middleware: [offset(6), flip(), shift({ padding: 8 })],
            }).then(({ x, y }) => Object.assign(tooltip.style, { left: `${x}px`, top: `${y}px` }))
        })
    }
}
