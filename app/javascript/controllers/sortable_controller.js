import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["item"]
  static values = {
    url: String,
    // Ask for a Turbo Stream back once the new order is saved, for pages
    // that show something else that follows it — "Plan your week"'s to-do
    // chart — so it updates in place and the page keeps its scroll.
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
        ...(this.refreshValue ? { "Accept": "text/vnd.turbo-stream.html" } : {}),
        ...(token ? { "X-CSRF-Token": token } : {})
      },
      body: JSON.stringify({ order: order })
    }).then(async response => {
      if (this.refreshValue && response.ok) Turbo.renderStreamMessage(await response.text())
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