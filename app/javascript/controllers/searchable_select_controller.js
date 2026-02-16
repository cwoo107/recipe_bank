import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["select", "searchInput", "dropdown", "option"]
    static values = {
        placeholder: { type: String, default: "Search..." }
    }

    connect() {
        this.originalSelect = this.selectTarget
        this.selectedValue = this.originalSelect.value
        this.options = Array.from(this.originalSelect.options).map(opt => ({
            value: opt.value,
            text: opt.text,
            isFavorite: opt.dataset.favorite === 'true'
        }))

        this.buildCustomSelect()
        this.originalSelect.style.display = 'none'
    }

    buildCustomSelect() {
        const wrapper = document.createElement('div')
        wrapper.className = 'relative'
        wrapper.dataset.searchableSelectTarget = 'wrapper'

        // Search input
        const input = document.createElement('input')
        input.type = 'text'
        input.placeholder = this.placeholderValue
        input.className = 'block w-full rounded-lg bg-white dark:bg-white/5 px-3 py-2.5 text-gray-900 dark:text-white border border-gray-300 dark:border-white/10 focus:border-[#5f734c] dark:focus:border-[#7a8f62] focus:ring-2 focus:ring-[#5f734c]/20 dark:focus:ring-[#7a8f62]/20 outline-none transition'
        input.dataset.searchableSelectTarget = 'searchInput'
        input.dataset.action = 'input->searchable-select#filterOptions focus->searchable-select#showDropdown'

        // Dropdown container
        const dropdown = document.createElement('div')
        dropdown.className = 'absolute z-50 w-full mt-1 text-sm bg-white border border-gray-300 dark:border-gray-600 shadow-sm dark:bg-gray-800 dark:text-gray-100 rounded-md shadow-lg max-h-60 overflow-y-auto hidden'
        dropdown.dataset.searchableSelectTarget = 'dropdown'

        // Build options
        this.options.forEach(opt => {
            if (!opt.value) return // Skip blank option

            const optionDiv = document.createElement('div')
            optionDiv.className = 'px-3 py-2 text-sm cursor-pointer hover:bg-blue-50 dark:hover:bg-gray-700 transition-colors flex items-center gap-2'

            // Add star for favorites
            if (opt.isFavorite) {
                const star = document.createElement('span')
                star.className = 'text-yellow-500 shrink-0'
                star.innerHTML = `<svg viewBox="0 0 20 20" fill="currentColor" class="size-4" aria-hidden="true">
                    <path fill-rule="evenodd" d="M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401Z" clip-rule="evenodd" />
                </svg>`
                optionDiv.appendChild(star)
            }

            const textSpan = document.createElement('span')
            textSpan.textContent = opt.text
            optionDiv.appendChild(textSpan)

            optionDiv.dataset.value = opt.value
            optionDiv.dataset.favorite = opt.isFavorite
            optionDiv.dataset.searchableSelectTarget = 'option'
            optionDiv.dataset.action = 'click->searchable-select#selectOption'

            if (opt.value === this.selectedValue) {
                optionDiv.classList.add('bg-blue-100', 'dark:bg-blue-900', 'font-medium')
            }

            dropdown.appendChild(optionDiv)
        })

        wrapper.appendChild(input)
        wrapper.appendChild(dropdown)
        this.originalSelect.parentNode.insertBefore(wrapper, this.originalSelect)

        // Set initial display value
        const selectedOption = this.options.find(opt => opt.value === this.selectedValue)
        if (selectedOption) {
            input.value = selectedOption.text
        }

        // Close dropdown when clicking outside
        document.addEventListener('click', this.handleClickOutside.bind(this))
    }

    filterOptions(event) {
        const searchTerm = event.target.value.toLowerCase()

        this.optionTargets.forEach(option => {
            const text = option.textContent.toLowerCase()
            if (text.includes(searchTerm)) {
                option.classList.remove('hidden')
            } else {
                option.classList.add('hidden')
            }
        })

        this.showDropdown()
    }

    showDropdown() {
        this.dropdownTarget.classList.remove('hidden')
    }

    hideDropdown() {
        this.dropdownTarget.classList.add('hidden')
    }

    selectOption(event) {
        const selectedValue = event.currentTarget.dataset.value
        const selectedText = event.currentTarget.querySelector('span:last-child')?.textContent || event.currentTarget.textContent

        // Update hidden select
        this.originalSelect.value = selectedValue

        // Update search input
        this.searchInputTarget.value = selectedText

        // Update visual selection
        this.optionTargets.forEach(opt => {
            opt.classList.remove('bg-blue-100', 'dark:bg-blue-900', 'font-medium')
        })
        event.currentTarget.classList.add('bg-blue-100', 'dark:bg-blue-900', 'font-medium')

        // Hide dropdown
        this.hideDropdown()

        // Trigger change event for dynamic-filter controller
        this.originalSelect.dispatchEvent(new Event('change', { bubbles: true }))
    }

    handleClickOutside(event) {
        if (!this.element.contains(event.target)) {
            this.hideDropdown()
        }
    }

    disconnect() {
        document.removeEventListener('click', this.handleClickOutside.bind(this))
    }
}