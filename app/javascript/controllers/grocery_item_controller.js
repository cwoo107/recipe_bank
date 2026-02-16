import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["form", "units"]

    increment(event) {
        event.preventDefault()
        const currentUnits = parseInt(this.unitsTarget.value)
        this.unitsTarget.value = currentUnits + 1
        this.submitForm()
    }

    decrement(event) {
        event.preventDefault()
        const currentUnits = parseInt(this.unitsTarget.value)
        if (currentUnits > 1) {
            this.unitsTarget.value = currentUnits - 1
            this.submitForm()
        }
    }

    toggleCheck(event) {
        // Store scroll position before submit
        const scrollPosition = window.scrollY

        // Restore scroll after turbo processes the response
        const restoreScroll = () => {
            window.scrollTo(0, scrollPosition)
            document.removeEventListener('turbo:render', restoreScroll)
        }

        document.addEventListener('turbo:render', restoreScroll)

        this.submitForm()
    }

    submitForm() {
        const scrollPosition = window.scrollY

        const restoreScroll = () => {
            window.scrollTo(0, scrollPosition)
            document.removeEventListener('turbo:render', restoreScroll)
        }

        document.addEventListener('turbo:render', restoreScroll)

        this.formTarget.requestSubmit()
    }
}