// app/javascript/controllers/calendar_source_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["urlSection", "instructions"]

    connect() {
        this.updateInstructions()
    }

    providerChanged() {
        this.updateInstructions()
    }

    updateInstructions() {
        const selected = this.element.querySelector('input[name="calendar_source[provider]"]:checked')
        const provider = selected?.value

        // Show the URL section for all providers
        this.urlSectionTarget.classList.remove("hidden")

        // Show only the matching instruction block
        this.instructionsTarget.querySelectorAll("[data-provider]").forEach(el => {
            el.classList.toggle("hidden", el.dataset.provider !== provider)
        })
    }
}