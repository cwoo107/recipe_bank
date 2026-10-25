import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["item"]
  static values = {
    url: String,
    // Reload the page (a morphing refresh) once the new order is saved, for
    // pages that show something else that follows it — "Plan your week"'s
    // to-do chart.
    refresh: Boolean
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

    // Send to server. The CSRF meta tag is absent when forgery protection is
    // off, and reading .content off null threw the whole handler away.
    const token = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { "X-CSRF-Token": token } : {})
      },
      body: JSON.stringify({ order: order })
    }).then(response => {
      if (this.refreshValue && response.ok) Turbo.visit(window.location.href, { action: "replace" })
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