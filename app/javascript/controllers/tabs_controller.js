import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["tab", "panel"]

    show(event) {
        const panelId = event.currentTarget.dataset.tabsPanel
        this.panelTargets.forEach(p => p.classList.toggle("hidden", p.id !== panelId))
        this.tabTargets.forEach(t => {
            const active = t.dataset.tabsPanel === panelId
            t.classList.toggle("border-[#5f734c]", active)
            t.classList.toggle("text-[#5f734c]", active)
            t.classList.toggle("dark:text-[#7a8f62]", active)
            t.classList.toggle("dark:border-[#7a8f62]", active)
            t.classList.toggle("border-transparent", !active)
            t.classList.toggle("text-gray-500", !active)
        })
    }
}