import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["formCard"]

  showForm(event) {
    event.preventDefault()
    this.formCardTarget.classList.remove("hidden")
    
    const input = this.formCardTarget.querySelector('input[type="text"]')
    if (input) input.focus()
  }

  hideForm(event) {
    this.formCardTarget.classList.add("hidden")
    
    // Clear form
    const form = this.formCardTarget.querySelector('form')
    if (form) {
      form.reset()
      const colorInput = form.querySelector('input[type="color"]')
      if (colorInput) colorInput.value = '#7a8f62'
    }
  }
}
