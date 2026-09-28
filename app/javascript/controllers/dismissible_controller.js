import { Controller } from "@hotwired/stimulus"

// Removes its element — for inline notices with a "No thanks" button.
export default class extends Controller {
    dismiss() {
        this.element.remove()
    }
}
