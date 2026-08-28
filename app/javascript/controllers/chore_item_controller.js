import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["form"]

    toggleCheck(event) {
        this.formTarget.requestSubmit()
    }
}
