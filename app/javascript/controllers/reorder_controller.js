// app/javascript/controllers/reorder_controller.js
//
// Drag-to-reorder for a list of whole blocks — the restock checklist's
// category cards. The same setup as the chore board's category rows
// (chore_board_controller.js), just laid out as a grid: each block carries
// data-reorder-id and is dragged by an element inside it with the
// .reorder-handle class (kept separate from .sortable-handle, which the
// cards' own items use to move between cards). Anything without
// data-reorder-id (the "Add a category" tile) stays put. On drop, POSTs
// { order: [ids...] } to data-reorder-url-value.

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
    static values = { url: String }

    connect() {
        this.sortable = Sortable.create(this.element, {
            group: "reorder-blocks",
            handle: ".reorder-handle",
            draggable: "[data-reorder-id]",
            animation: 150,
            onEnd: this.end.bind(this)
        })
    }

    disconnect() {
        if (this.sortable) this.sortable.destroy()
    }

    end(event) {
        if (event.oldIndex === event.newIndex) return

        const order = Array.from(this.element.querySelectorAll("[data-reorder-id]"))
            .map((el) => el.dataset.reorderId)
        const token = document.querySelector("meta[name='csrf-token']")?.content

        fetch(this.urlValue, {
            method: "POST",
            headers: { "Content-Type": "application/json", ...(token ? { "X-CSRF-Token": token } : {}) },
            body: JSON.stringify({ order })
        })
    }
}
