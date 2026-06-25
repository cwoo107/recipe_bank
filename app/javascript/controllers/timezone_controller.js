import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
        if (timezone) {
            document.cookie = `browser_timezone=${timezone};path=/;max-age=31536000`
        }
    }
}