import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        delay: { type: Number, default: 3000 }
    }

    connect() {
        this.timeout = setTimeout(() => {
            this.dismiss()
        }, this.delayValue)
    }

    disconnect() {
        clearTimeout(this.timeout)
    }

    dismiss() {
        this.element.style.opacity = '0'
        this.element.style.transform = 'translateX(100%)'
        setTimeout(() => {
            this.element.remove()
        }, 300)
    }
}