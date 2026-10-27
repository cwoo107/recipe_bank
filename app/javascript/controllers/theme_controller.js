import { Controller } from "@hotwired/stimulus"

// The light / system / dark switch (shared/_theme_switch). Applies the
// choice right away (layouts/_theme's window.applyTheme), then saves it —
// to a cookie, and to the account when signed in (ThemesController).
export default class extends Controller {
    static targets = ["option"]
    static values = { url: String }

    // A page restored from Turbo's cache may show an older choice.
    connect() {
        this.mark(document.documentElement.dataset.theme)
    }

    choose({ params: { theme } }) {
        document.documentElement.dataset.theme = theme
        window.applyTheme?.()
        this.mark(theme)

        const token = document.querySelector("meta[name='csrf-token']")?.content
        fetch(this.urlValue, {
            method: "PATCH",
            headers: { "X-CSRF-Token": token, "Content-Type": "application/json", "Accept": "application/json" },
            body: JSON.stringify({ theme })
        })
    }

    mark(theme) {
        this.optionTargets.forEach(option => {
            option.setAttribute("aria-pressed", option.dataset.themeThemeParam === theme)
        })
    }
}
