import { Controller } from "@hotwired/stimulus"

// Handles the "add to collection" dropdown on recipe cards.
// Fetches the dropdown content via a Turbo Frame on first open.
export default class extends Controller {
  static targets = ["menu", "frame"]
  static values  = { recipeId: Number, open: { type: Boolean, default: false } }

  connect() {
    document.addEventListener("click", this.closeOnOutsideClick.bind(this))
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick.bind(this))
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.openValue = !this.openValue
  }

  openValueChanged() {
    if (this.hasMenuTarget) {
      this.menuTarget.classList.toggle("hidden", !this.openValue)
    }
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.openValue = false
    }
  }
}
