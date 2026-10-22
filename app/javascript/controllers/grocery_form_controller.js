import { Controller } from "@hotwired/stimulus"

// The grocery list's "Add to list" form: an ingredient (picked, or typed in
// as a new one), or — on the "Make a Note" tab — a note. The entry hidden
// field tells GroceryListsController#create which one to save.
export default class extends Controller {
    static targets = ["tab", "entryInput", "ingredientSection", "noteSection", "unitsInput", "noteInput"]

    choose(event) {
        const entry = event.currentTarget.dataset.entry
        this.entryInputTarget.value = entry

        const note = entry === "note"
        this.ingredientSectionTarget.classList.toggle("hidden", note)
        this.noteSectionTarget.classList.toggle("hidden", !note)
        // Units are required for an ingredient; a note has none.
        this.unitsInputTarget.disabled = note
        this.noteInputTarget.required = note

        this.tabTargets.forEach(tab => {
            const active = tab.dataset.entry === entry
            tab.classList.toggle("border-[#5f734c]", active)
            tab.classList.toggle("text-[#5f734c]", active)
            tab.classList.toggle("dark:border-[#7a8f62]", active)
            tab.classList.toggle("dark:text-[#7a8f62]", active)
            tab.classList.toggle("border-transparent", !active)
            tab.classList.toggle("text-gray-500", !active)
        })

        if (note) this.noteInputTarget.focus()
    }
}
