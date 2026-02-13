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

    toggleCheck() {
        this.submitForm()
    }

    submitForm() {
        this.formTarget.requestSubmit()
    }
}