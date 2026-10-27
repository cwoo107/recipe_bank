import { Controller } from "@hotwired/stimulus"

// Copies the source field's value, and says so on the button for a moment.
// Admin beta invite links (admin/beta_invites).
export default class extends Controller {
    static targets = ["source", "button"]

    async copy() {
        const text = this.sourceTarget.value
        try {
            await navigator.clipboard.writeText(text)
        } catch {
            // No clipboard permission (or not https) — select it to copy by hand.
            this.sourceTarget.select()
            return
        }

        const label = this.buttonTarget.textContent
        this.buttonTarget.textContent = "Copied!"
        clearTimeout(this.timeout)
        this.timeout = setTimeout(() => { this.buttonTarget.textContent = label }, 2000)
    }

    select() {
        this.sourceTarget.select()
    }
}
