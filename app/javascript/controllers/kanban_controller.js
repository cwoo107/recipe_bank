// app/javascript/controllers/kanban_controller.js
//
// Wraps SortableJS for the kanban board, enabling drag between columns.
// Each column uses data-controller="kanban" and data-kanban-url-value pointing
// to reorder_todos_path.  Cross-column moves call the move endpoint on the todo.

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
    static targets = ["item"]
    static values  = { url: String }

    connect() {
        this.sortable = Sortable.create(this.element, {
            group:     "kanban",          // shared group enables cross-column drag
            handle:    ".sortable-handle",
            animation: 150,
            onEnd:     this.end.bind(this)
        })
    }

    end(event) {
        const id        = event.item.dataset.id
        const fromList  = event.from
        const toList    = event.to
        const newStatus = toList.dataset.status
        const newIndex  = event.newIndex + 1  // 1-based position

        if (fromList === toList) {
            // Same column: just reorder
            const order = this.#orderFromList(toList)
            fetch(this.urlValue, {
                method:  "POST",
                headers: this.#headers(),
                body:    JSON.stringify({ status: newStatus, order })
            })
        } else {
            // Cross-column move: update status + position on the todo
            fetch(`/todos/${id}/move`, {
                method:  "POST",
                headers: this.#headers(),
                body:    JSON.stringify({ status: newStatus, position: newIndex })
            })

            // Also reorder the source column
            const fromStatus = fromList.dataset.status
            const fromOrder  = this.#orderFromList(fromList)
            fetch(this.urlValue, {
                method:  "POST",
                headers: this.#headers(),
                body:    JSON.stringify({ status: fromStatus, order: fromOrder })
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
        const hasTodos      = list.querySelectorAll("[data-id]").length > 0
        const placeholder   = list.querySelector("[data-placeholder]")

        if (hasTodos) {
            // Hide existing placeholder if present
            if (placeholder) placeholder.remove()
        } else {
            // Add placeholder if not already there
            if (!placeholder) {
                const el = document.createElement("div")
                el.dataset.placeholder = ""
                el.className = "flex-1 flex items-center justify-center min-h-20 rounded-md border-2 border-dashed border-gray-200 dark:border-white/10"
                el.innerHTML = '<p class="text-sm text-gray-400 dark:text-gray-600 italic">No tasks here yet</p>'
                list.appendChild(el)
            }
        }
    }
}