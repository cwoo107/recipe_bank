import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["totalBtn", "perServingBtn", "totalView", "perServingView"]

    showTotal() {
        this.totalViewTarget.classList.remove("hidden")
        this.perServingViewTarget.classList.add("hidden")
        this.totalBtnTarget.classList.add("bg-[#5f734c]", "text-white", "dark:bg-[#7a8f62]")
        this.totalBtnTarget.classList.remove("text-gray-500", "dark:text-gray-400")
        this.perServingBtnTarget.classList.remove("bg-[#5f734c]", "text-white", "dark:bg-[#7a8f62]")
        this.perServingBtnTarget.classList.add("text-gray-500", "dark:text-gray-400")
    }

    showPerServing() {
        this.perServingViewTarget.classList.remove("hidden")
        this.totalViewTarget.classList.add("hidden")
        this.perServingBtnTarget.classList.add("bg-[#5f734c]", "text-white", "dark:bg-[#7a8f62]")
        this.perServingBtnTarget.classList.remove("text-gray-500", "dark:text-gray-400")
        this.totalBtnTarget.classList.remove("bg-[#5f734c]", "text-white", "dark:bg-[#7a8f62]")
        this.totalBtnTarget.classList.add("text-gray-500", "dark:text-gray-400")
    }
}