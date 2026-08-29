// app/javascript/controllers/kanban_controller.js
//
// Wraps SortableJS for a kanban-style board, enabling drag between columns.
// Each column uses data-controller="kanban", data-kanban-url-value pointing
// to the reorder endpoint, and data-kanban-move-url-value pointing to the
// per-item move endpoint (with ":id" as a placeholder for the item's id).
// data-kanban-param-value names the JSON key for the column identifier
// (defaults to "status"; e.g. "category" for the restock checklist).

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
    static targets = ["item"]
    static values  = {
        url:     String,
        moveUrl: String,
        param:   { type: String, default: "status" }
    }

    connect() {
        this.sortable = Sortable.create(this.element, {
            group:     "kanban",          // shared group enables cross-column drag
            handle:    ".sortable-handle",
            animation: 150,
            onEnd:     this.end.bind(this)
        })
    }

    end(event) {
        const id         = event.item.dataset.id
        const fromList   = event.from
        const toList     = event.to
        const newColumn  = toList.dataset.column
        const newIndex   = event.newIndex + 1  // 1-based position

        if (fromList === toList) {
            // Same column: just reorder
            const order = this.#orderFromList(toList)
            fetch(this.urlValue, {
                method:  "POST",
                headers: this.#headers(),
                body:    JSON.stringify({ [this.paramValue]: newColumn, order })
            })
        } else {
            // Cross-column move: update the item's column + position
            fetch(this.moveUrlValue.replace(":id", id), {
                method:  "POST",
                headers: this.#headers(),
                body:    JSON.stringify({ [this.paramValue]: newColumn, position: newIndex })
            })

            // Also reorder the source column
            const fromColumn = fromList.dataset.column
            const fromOrder  = this.#orderFromList(fromList)
            fetch(this.urlValue, {
                method:  "POST",
                headers: this.#headers(),
                body:    JSON.stringify({ [this.paramValue]: fromColumn, order: fromOrder })
            })

            // Update placeholders for both affected columns
            this.#updatePlaceholder(fromList)
            this.#updatePlaceholder(toList)
        }
    }

    disconnect() {
        if (this.sortable) this.sortable.destroy()
    }

    // -----------------------------------------------------------------------

    #orderFromList(list) {
        return Array.from(list.querySelectorAll("[data-id]"))
            .map(el => el.dataset.id)
    }

    #headers() {
        return {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
        }
    }

    #updatePlaceholder(list) {
        const hasItems      = list.querySelectorAll("[data-id]").length > 0
        const placeholder   = list.querySelector("[data-placeholder]")
        const emptyText     = list.dataset.emptyText || "Nothing here yet"

        if (hasItems) {
            // Hide existing placeholder if present
            if (placeholder) placeholder.remove()
        } else {
            // Add placeholder if not already there
            if (!placeholder) {
                const el = document.createElement("div")
                el.dataset.placeholder = ""
                el.className = "flex-1 flex items-center justify-center min-h-20 rounded-md border-2 border-dashed border-gray-200 dark:border-white/10"
                el.innerHTML = `<p class="text-sm text-gray-400 dark:text-gray-600 italic">${emptyText}</p>`
                list.appendChild(el)
            }
        }
    }
}
