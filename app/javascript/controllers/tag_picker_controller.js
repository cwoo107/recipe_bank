import { Controller } from "@hotwired/stimulus"

// A search-and-select bar for tags (shared/_tag_picker). Typing lists the
// matching tags; picking one adds it to the comma-separated list in the bar
// and clears the typing for the next one. With `creatable`, a name that
// isn't a tag yet can be added too, for the server to create.
//
// The picked names go to the hidden `field` as "Yard, Paperwork" — that's
// what the form submits.
//
// Keys: ↑/↓ move through the list, Enter or "," adds, Backspace in an empty
// bar takes the last tag off, Escape closes the list.
export default class extends Controller {
    static targets = ["field", "input", "list", "menu"]
    static values  = {
        options:   Array,   // [{ name: "Yard", color: "#76a39b" }, ...]
        creatable: { type: Boolean, default: true }
    }

    connect() {
        this.selected = this.fieldTarget.value.split(",").map(name => name.trim()).filter(Boolean)
        this.highlighted = -1
        this.renderList()

        // Words still in the bar when the form is sent count as a tag too.
        this.form = this.element.closest("form")
        this.commitOnSubmit = () => this.#commit(this.inputTarget.value)
        this.form?.addEventListener("submit", this.commitOnSubmit)

        // form.reset() (the new-task dialog clearing itself after a save)
        // leaves hidden fields alone, so put the tags back to how they started.
        this.initial = [ ...this.selected ]
        this.restoreOnReset = () => {
            this.selected = [ ...this.initial ]
            this.inputTarget.value = ""
            this.close()
            this.#changed()
        }
        this.form?.addEventListener("reset", this.restoreOnReset)
    }

    disconnect() {
        this.form?.removeEventListener("submit", this.commitOnSubmit)
        this.form?.removeEventListener("reset", this.restoreOnReset)
    }

    focus(event) {
        if (event.target === event.currentTarget) this.inputTarget.focus()
    }

    search() {
        const typed = this.inputTarget.value.trim()
        const query = typed.toLowerCase()
        const taken = new Set(this.selected.map(name => name.toLowerCase()))

        this.matches = this.optionsValue
            .filter(option => !taken.has(option.name.toLowerCase()))
            .filter(option => option.name.toLowerCase().includes(query))
            .slice(0, 8)
        const exact = this.optionsValue.some(option => option.name.toLowerCase() === query)
        this.newName = this.creatableValue && typed && !exact && !taken.has(query) ? typed : null

        this.highlighted = this.matches.length || this.newName ? 0 : -1
        this.renderMenu()
    }

    keydown(event) {
        const count = this.#items().length

        switch (event.key) {
            case "ArrowDown":
            case "ArrowUp":
                if (this.menuTarget.hidden) { this.search(); break }
                if (!count) break
                event.preventDefault()
                this.highlighted = (this.highlighted + (event.key === "ArrowDown" ? 1 : -1) + count) % count
                this.renderMenu()
                break
            case "Enter":
                // An empty bar lets Enter submit the form as usual.
                if (!this.inputTarget.value.trim() && this.menuTarget.hidden) break
                event.preventDefault()
                this.#pickHighlighted()
                break
            case ",":
                event.preventDefault()
                this.#commit(this.inputTarget.value)
                break
            case "Backspace":
                if (this.inputTarget.value === "" && this.selected.length) {
                    this.selected.pop()
                    this.#changed()
                }
                break
            case "Escape":
                if (!this.menuTarget.hidden) {
                    event.preventDefault()
                    this.close()
                }
                break
        }
    }

    // On mousedown, not click, so the bar keeps focus (no blur closing the
    // list first) and the next tag can be typed straight away.
    pick(event) {
        event.preventDefault()
        this.highlighted = Number(event.currentTarget.dataset.index)
        this.#pickHighlighted()
    }

    remove(event) {
        this.selected.splice(Number(event.currentTarget.dataset.index), 1)
        this.#changed()
        this.inputTarget.focus()
    }

    close() {
        this.menuTarget.hidden = true
        this.inputTarget.setAttribute("aria-expanded", "false")
    }

    // ── Rendering ──────────────────────────────────────────────────────

    renderList() {
        this.listTarget.replaceChildren(...this.selected.map((name, index) => {
            const token = document.createElement("span")
            token.className = "inline-flex items-center gap-0.5 text-sm text-gray-900 dark:text-white"

            const color = this.#colorFor(name)
            if (color) token.append(this.#dot(color))
            token.append(name)

            const remove = document.createElement("button")
            remove.type = "button"
            remove.className = "rounded text-gray-400 hover:text-dusty-rose-600 dark:hover:text-dusty-rose-400"
            remove.setAttribute("aria-label", `Remove ${name}`)
            remove.dataset.index = index
            remove.dataset.action = "tag-picker#remove"
            remove.innerHTML = `<svg viewBox="0 0 16 16" fill="currentColor" class="size-3.5" aria-hidden="true"><path d="M5.28 4.22a.75.75 0 0 0-1.06 1.06L6.94 8l-2.72 2.72a.75.75 0 1 0 1.06 1.06L8 9.06l2.72 2.72a.75.75 0 1 0 1.06-1.06L9.06 8l2.72-2.72a.75.75 0 0 0-1.06-1.06L8 6.94 5.28 4.22Z" /></svg>`
            token.append(remove, ",")
            return token
        }))
    }

    renderMenu() {
        const items = this.#items()
        if (!items.length) return this.close()

        this.menuTarget.replaceChildren(...items.map((item, index) => {
            const li = document.createElement("li")
            li.id = `${this.menuTarget.id}-${index}`
            li.setAttribute("role", "option")
            li.setAttribute("aria-selected", index === this.highlighted)
            li.dataset.index = index
            li.dataset.action = "mousedown->tag-picker#pick"
            li.className = `flex cursor-pointer items-center gap-2 px-3 py-2 text-sm ${
                index === this.highlighted ? "bg-[#5f734c]/10 dark:bg-white/10" : ""
            } ${item.isNew ? "font-medium text-[#5f734c] dark:text-[#95a97d]" : "text-gray-900 dark:text-white"}`

            if (item.isNew) {
                li.textContent = `Add “${item.name}”`
            } else {
                if (item.color) li.append(this.#dot(item.color))
                li.append(item.name)
            }
            return li
        }))

        this.menuTarget.hidden = false
        this.inputTarget.setAttribute("aria-expanded", "true")
        if (this.highlighted >= 0) this.inputTarget.setAttribute("aria-activedescendant", `${this.menuTarget.id}-${this.highlighted}`)
    }

    // ── Helpers ────────────────────────────────────────────────────────

    #items() {
        if (this.menuTarget.hidden && !this.matches) return []
        const items = [ ...(this.matches || []) ]
        if (this.newName) items.push({ name: this.newName, isNew: true })
        return items
    }

    #pickHighlighted() {
        const item = this.#items()[this.highlighted]
        this.#commit(item ? item.name : this.inputTarget.value)
    }

    // Adds a name — an existing tag's own spelling when it matches one —
    // unless it's blank, already in the list, or new when new ones aren't
    // allowed. Then clears the bar for the next one.
    #commit(raw) {
        const typed = raw.trim()
        if (typed) {
            const existing = this.optionsValue.find(option => option.name.toLowerCase() === typed.toLowerCase())
            const name = existing ? existing.name : (this.creatableValue ? typed : null)
            if (name && !this.selected.some(picked => picked.toLowerCase() === name.toLowerCase())) {
                this.selected.push(name)
            }
        }
        this.inputTarget.value = ""
        this.matches = null
        this.newName = null
        this.close()
        this.#changed()
    }

    #changed() {
        this.fieldTarget.value = this.selected.join(", ")
        this.renderList()
    }

    #colorFor(name) {
        return this.optionsValue.find(option => option.name.toLowerCase() === name.toLowerCase())?.color
    }

    #dot(color) {
        const dot = document.createElement("span")
        dot.className = "mr-1 inline-block size-2 shrink-0 rounded-full"
        dot.style.backgroundColor = color
        dot.setAttribute("aria-hidden", "true")
        return dot
    }
}
