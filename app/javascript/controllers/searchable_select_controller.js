import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["select", "searchInput", "dropdown", "option",
                       "searchTab", "collectionTab", "otherTab", "sourceSelect", "collectionPicker", "tagChip",
                       "publicToggle", "newName"]
    static values = {
        placeholder: { type: String, default: "Search..." },
        // Creatable pickers (the recipe page's ingredient picker) also take a
        // name that isn't one of the options: it goes in the newName hidden
        // field for the server to create, and the dropdown offers it as
        // createLabel ("%s" is the typed text).
        creatable: { type: Boolean, default: false },
        createLabel: { type: String, default: "Add “%s”" }
    }

    connect() {
        this.originalSelect = this.selectTarget
        this.selectedValue = this.originalSelect.value
        this.selectedTagIds = new Set()
        this.source = "search"
        // Recipes outside the household are rendered but hidden until asked for.
        this.includePublic = this.hasPublicToggleTarget ? this.publicToggleTarget.checked : true
        this.options = Array.from(this.originalSelect.options).map(opt => ({
            value: opt.value,
            text: opt.text,
            isFavorite: opt.dataset.favorite === 'true',
            isPublic: opt.dataset.public === 'true',
            tagIds: opt.dataset.tagIds || "",
            collectionIds: opt.dataset.collectionIds || ""
        }))

        this.buildCustomSelect()
        this.originalSelect.style.display = 'none'

        // Apply the starting filters (e.g. public recipes hidden while the
        // toggle is off) before anything is shown — otherwise focusing the
        // empty search box lists every option until a filter first changes.
        this.applyFilters({ show: false })
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

            // Badge goes before the text so selectOption's `span:last-child`
            // lookup still finds the recipe title.
            if (opt.isPublic) {
                const badge = document.createElement('span')
                badge.className = 'shrink-0 rounded-full bg-gray-100 px-1.5 py-0.5 text-[10px] font-medium text-gray-500 dark:bg-white/10 dark:text-gray-400'
                badge.textContent = 'Public'
                optionDiv.appendChild(badge)
            }

            const textSpan = document.createElement('span')
            textSpan.textContent = opt.text
            optionDiv.appendChild(textSpan)

            optionDiv.dataset.value = opt.value
            optionDiv.dataset.title = opt.text
            optionDiv.dataset.favorite = opt.isFavorite
            optionDiv.dataset.public = opt.isPublic
            optionDiv.dataset.tagIds = opt.tagIds
            optionDiv.dataset.collectionIds = opt.collectionIds
            optionDiv.dataset.searchableSelectTarget = 'option'
            optionDiv.dataset.action = 'click->searchable-select#selectOption'

            if (opt.value === this.selectedValue) {
                optionDiv.classList.add('bg-blue-100', 'dark:bg-blue-900', 'font-medium')
            }

            dropdown.appendChild(optionDiv)
        })

        if (this.creatableValue) {
            this.createOption = document.createElement('div')
            this.createOption.className = 'hidden px-3 py-2 text-sm cursor-pointer font-medium text-[#5f734c] dark:text-[#95a97d] hover:bg-blue-50 dark:hover:bg-gray-700 transition-colors border-b border-gray-200 dark:border-gray-700'
            this.createOption.dataset.action = 'click->searchable-select#chooseNew'
            dropdown.prepend(this.createOption)
        }

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

    filterOptions() {
        if (this.creatableValue) this.syncTypedName()
        this.applyFilters()
    }

    // Creatable pickers: editing the text un-picks whatever was picked, an
    // exact (case-insensitive) match picks that option, and anything else is
    // a new name — offered at the top of the dropdown and sent as newName.
    syncTypedName() {
        const typed = this.searchInputTarget.value.trim()
        const exact = typed && this.options.find(opt => opt.value && opt.text.toLowerCase() === typed.toLowerCase())

        this.originalSelect.value = exact ? exact.value : ''
        this.optionTargets.forEach(opt => {
            opt.classList.toggle('bg-blue-100', opt.dataset.value === this.originalSelect.value)
            opt.classList.toggle('dark:bg-blue-900', opt.dataset.value === this.originalSelect.value)
            opt.classList.toggle('font-medium', opt.dataset.value === this.originalSelect.value)
        })
        if (this.hasNewNameTarget) this.newNameTarget.value = exact ? '' : typed

        this.createOption.textContent = this.createLabelValue.replace('%s', typed)
        this.createOption.classList.toggle('hidden', !typed || !!exact)
    }

    // Clicking "Add “…” as a new ingredient": keep the typed name and move on
    // to the amount.
    chooseNew() {
        this.syncTypedName()
        this.hideDropdown()
        this.element.querySelector('input[type=number]')?.focus()
    }

    // Toggles a tag chip on/off (multi-select, OR'd together) and re-filters.
    toggleTag(event) {
        const chip = event.currentTarget
        const tagId = chip.dataset.tagId

        if (this.selectedTagIds.has(tagId)) {
            this.selectedTagIds.delete(tagId)
            chip.classList.add('opacity-60')
            chip.classList.remove('ring-1', 'ring-current')
        } else {
            this.selectedTagIds.add(tagId)
            chip.classList.remove('opacity-60')
            chip.classList.add('ring-1', 'ring-current')
        }

        this.applyFilters()
    }

    showSearch() {
        this.source = "search"
        if (this.hasCollectionPickerTarget) this.collectionPickerTarget.classList.add('hidden')
        this.setActiveTab(this.searchTabTarget, this.collectionTabTarget, ...this.otherTabTargets)
        if (this.hasSourceSelectTarget) this.sourceSelectTarget.value = "search"
        this.applyFilters()
    }

    showCollection() {
        this.source = "collection"
        if (this.hasCollectionPickerTarget) this.collectionPickerTarget.classList.remove('hidden')
        this.setActiveTab(this.collectionTabTarget, this.searchTabTarget, ...this.otherTabTargets)
        if (this.hasSourceSelectTarget) this.sourceSelectTarget.value = "collection"
        this.applyFilters()
    }

    // Tabs for panels outside this picker (the meal form's "Make a Note",
    // data-source="note"). This side just marks the tab; whoever owns the
    // panel shows it.
    showOther(event) {
        this.activateOther(event.currentTarget)
    }

    activateOther(tab) {
        if (this.hasCollectionPickerTarget) this.collectionPickerTarget.classList.add('hidden')
        this.hideDropdown()
        this.setActiveTab(tab, this.searchTabTarget, this.collectionTabTarget,
                          ...this.otherTabTargets.filter(other => other !== tab))
        if (this.hasSourceSelectTarget) this.sourceSelectTarget.value = tab.dataset.source
    }

    // Mirrors the mobile <select> fallback shown below the sm breakpoint.
    sourceSelectChanged(event) {
        const other = this.otherTabTargets.find(tab => tab.dataset.source === event.target.value)

        if (other) {
            this.activateOther(other)
        } else if (event.target.value === "collection") {
            this.showCollection()
        } else {
            this.showSearch()
        }
    }

    // Widens the pool from "our household's recipes" to include public ones.
    togglePublic(event) {
        this.includePublic = event.target.checked
        this.applyFilters()
    }

    collectionChanged(event) {
        this.selectedCollectionId = event.target.value
        this.applyFilters()
    }

    // Combines the typed search term with the pool/tag/collection filters above —
    // an option must satisfy all of them (text match, in the active recipe pool,
    // any selected tag, and — in "collection" mode — membership in the chosen
    // collection).
    applyFilters({ show = true } = {}) {
        const term = this.hasSearchInputTarget ? this.searchInputTarget.value.toLowerCase() : ""

        this.optionTargets.forEach(option => {
            const text = (option.dataset.title || option.textContent).toLowerCase()
            const matchesText = !term || text.includes(term)

            let matchesTags = true
            if (this.selectedTagIds.size > 0) {
                const tagIds = (option.dataset.tagIds || "").split(",")
                matchesTags = tagIds.some(id => this.selectedTagIds.has(id))
            }

            let matchesCollection = true
            if (this.source === "collection") {
                const collectionIds = (option.dataset.collectionIds || "").split(",")
                matchesCollection = !!this.selectedCollectionId && collectionIds.includes(this.selectedCollectionId)
            }

            // Keep the current selection visible even if it's outside the pool.
            const matchesPool = this.includePublic ||
                                option.dataset.public !== 'true' ||
                                option.dataset.value === this.originalSelect.value

            option.classList.toggle('hidden', !(matchesText && matchesTags && matchesCollection && matchesPool))
        })

        if (show) this.showDropdown()
    }

    setActiveTab(active, ...inactives) {
        active.classList.add('border-[#5f734c]', 'text-[#5f734c]', 'dark:border-[#7a8f62]', 'dark:text-[#7a8f62]')
        active.classList.remove('border-transparent', 'text-gray-500', 'hover:border-gray-300', 'hover:text-gray-700',
                                 'dark:text-gray-400', 'dark:hover:border-white/20', 'dark:hover:text-gray-200')
        active.setAttribute('aria-current', 'page')

        inactives.forEach(inactive => {
            inactive.classList.remove('border-[#5f734c]', 'text-[#5f734c]', 'dark:border-[#7a8f62]', 'dark:text-[#7a8f62]')
            inactive.classList.add('border-transparent', 'text-gray-500', 'hover:border-gray-300', 'hover:text-gray-700',
                                    'dark:text-gray-400', 'dark:hover:border-white/20', 'dark:hover:text-gray-200')
            inactive.removeAttribute('aria-current')
        })
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
        if (this.hasNewNameTarget) this.newNameTarget.value = ''
        this.createOption?.classList.add('hidden')

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