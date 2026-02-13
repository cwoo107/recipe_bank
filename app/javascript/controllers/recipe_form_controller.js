import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tagForm", "ingredientForm"]

  toggleTagForm(event) {
    event.preventDefault()
    this.tagFormTarget.classList.toggle("hidden")
    
    if (!this.tagFormTarget.classList.contains("hidden")) {
      const input = this.tagFormTarget.querySelector('input[type="text"]')
      if (input) input.focus()
    }
  }

  hideTagForm(event) {
    event.preventDefault()
    this.tagFormTarget.classList.add("hidden")
    
    // Clear form inputs
    this.tagFormTarget.querySelectorAll('input').forEach(input => {
      if (input.type === 'text') input.value = ''
      if (input.type === 'color') input.value = '#7a8f62'
    })
  }

  toggleIngredientForm(event) {
    event.preventDefault()
    this.ingredientFormTarget.classList.toggle("hidden")
    
    if (!this.ingredientFormTarget.classList.contains("hidden")) {
      const input = this.ingredientFormTarget.querySelector('input[type="text"]')
      if (input) input.focus()
    }
  }

  hideIngredientForm(event) {
    event.preventDefault()
    this.ingredientFormTarget.classList.add("hidden")
    
    // Clear form inputs
    this.ingredientFormTarget.querySelectorAll('input, textarea').forEach(input => {
      if (input.type === 'checkbox') {
        input.checked = false
      } else if (input.type !== 'hidden') {
        input.value = ''
      }
    })
  }
}
