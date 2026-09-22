import { Controller } from "@hotwired/stimulus"

// Submits the form this is attached to as soon as a field changes, for
// inline edits that shouldn't need their own save button.
export default class extends Controller {
    submit() {
        this.element.requestSubmit()
    }
}
