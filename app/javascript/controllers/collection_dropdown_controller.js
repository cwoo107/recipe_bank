import { Controller } from "@hotwired/stimulus"

const OPENED = "collection-dropdown:opened"

const clamp = (value, min, max) => Math.min(Math.max(value, min), max)

// The "Add to a collection" dropdown on recipe rows.
//
// Only one is open at a time, it closes on an outside click, on Escape, and
// as soon as one of its buttons is used, and it flips above the trigger when
// there isn't room below.
export default class extends Controller {
    static targets = ["menu", "button"]
    static values  = { open: { type: Boolean, default: false } }

    connect() {
        // Keep the bound references: binding again in disconnect() produces a
        // different function, so the listeners would never come off.
        this.onDocumentClick = this.closeOnOutsideClick.bind(this)
        this.onKeydown       = this.closeOnEscape.bind(this)
        this.onOtherOpened   = this.closeUnlessMine.bind(this)
        this.onReposition    = this.positionMenu.bind(this)

        document.addEventListener("click", this.onDocumentClick)
        document.addEventListener("keydown", this.onKeydown)
        document.addEventListener(OPENED, this.onOtherOpened)
    }

    disconnect() {
        document.removeEventListener("click", this.onDocumentClick)
        document.removeEventListener("keydown", this.onKeydown)
        document.removeEventListener(OPENED, this.onOtherOpened)
        this.stopTracking()
    }

    toggle(event) {
        event.preventDefault()
        this.openValue = !this.openValue
    }

    close() {
        this.openValue = false
    }

    openValueChanged() {
        if (!this.hasMenuTarget) return

        this.menuTarget.classList.toggle("hidden", !this.openValue)
        if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", this.openValue)

        if (!this.openValue) {
            this.stopTracking()
            return
        }

        document.dispatchEvent(new CustomEvent(OPENED, { detail: { source: this.element } }))
        this.positionMenu()
        this.startTracking()
    }

    // While it's open the menu is positioned against the viewport, so it has
    // to be re-placed whenever the trigger moves under it. Capture phase so
    // scrolling inside a container counts, not just the window.
    startTracking() {
        if (this.tracking) return

        this.tracking = true
        window.addEventListener("scroll", this.onReposition, true)
        window.addEventListener("resize", this.onReposition)
    }

    stopTracking() {
        if (!this.tracking) return

        this.tracking = false
        window.removeEventListener("scroll", this.onReposition, true)
        window.removeEventListener("resize", this.onReposition)
    }

    closeUnlessMine(event) {
        if (event.detail?.source !== this.element) this.close()
    }

    closeOnOutsideClick(event) {
        if (!this.element.contains(event.target)) this.close()
    }

    closeOnEscape(event) {
        if (event.key === "Escape") this.close()
    }

    // Positioned against the viewport rather than the trigger's container:
    // both the recipe table and the mobile cards are `overflow-hidden`, which
    // would clip an absolutely positioned menu. Fixed escapes that, so the
    // whole dropdown stays visible wherever the row sits.
    //
    // Below the trigger and right-aligned by default, flipped above when
    // there's no room, then clamped so it can't leave the viewport. Inline
    // styles rather than utility classes, so there's nothing here for
    // Tailwind's class scanner to miss.
    positionMenu() {
        const menu   = this.menuTarget
        const anchor = (this.hasButtonTarget ? this.buttonTarget : this.element).getBoundingClientRect()
        const gap    = 4
        const margin = 8

        Object.assign(menu.style, {
            position: "fixed", top: "0px", left: "0px", right: "auto", bottom: "auto", margin: "0"
        })

        const { width, height } = menu.getBoundingClientRect()

        let top = anchor.bottom + gap
        const overflowsBelow = top + height > window.innerHeight - margin
        const roomAbove      = anchor.top - gap - height >= margin
        if (overflowsBelow && roomAbove) top = anchor.top - gap - height
        top = clamp(top, margin, Math.max(margin, window.innerHeight - height - margin))

        const left = clamp(anchor.right - width, margin,
                           Math.max(margin, window.innerWidth - width - margin))

        Object.assign(menu.style, { top: `${top}px`, left: `${left}px` })
    }
}
