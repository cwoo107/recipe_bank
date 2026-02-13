import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["item"]
  static values = {
    url: String
  }

  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: ".sortable-handle",
      animation: 150,
      onEnd: this.end.bind(this)
    })
  }

  end(event) {
    // Update step numbers immediately
    this.updateStepNumbers()

    // Get the new order of IDs
    const order = this.itemTargets.map(item => item.dataset.id)

    // Send to server
    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: JSON.stringify({ order: order })
    })
  }

  updateStepNumbers() {
    this.itemTargets.forEach((item, index) => {
      const numberCircle = item.querySelector(".step-number")
      if (numberCircle) {
        numberCircle.textContent = index + 1
      }
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }
}