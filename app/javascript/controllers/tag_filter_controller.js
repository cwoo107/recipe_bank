import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    // Auto-submit form when tag filter changes
    this.element.closest('form').requestSubmit()
  }
}
