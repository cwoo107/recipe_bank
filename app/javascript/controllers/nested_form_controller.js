import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  add(event) {
    event.preventDefault()
    
    const timestamp = new Date().getTime()
    const content = this.containerTarget.dataset.nestedFormTemplate
    const newContent = content.replace(/NEW_RECORD/g, timestamp)
    
    this.containerTarget.insertAdjacentHTML('beforeend', newContent)
  }

  remove(event) {
    event.preventDefault()
    const wrapper = event.target.closest('.nested-fields, [data-nested-form-target]')
    
    if (wrapper) {
      const idInput = wrapper.querySelector('input[name*="[id]"]')
      
      if (idInput) {
        // Existing record - mark for destruction
        const destroyInput = document.createElement('input')
        destroyInput.type = 'hidden'
        destroyInput.name = idInput.name.replace('[id]', '[_destroy]')
        destroyInput.value = '1'
        wrapper.appendChild(destroyInput)
        wrapper.style.display = 'none'
      } else {
        // New record - just remove from DOM
        wrapper.remove()
      }
    }
  }
}
