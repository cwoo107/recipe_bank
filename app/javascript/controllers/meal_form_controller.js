import { Controller } from "@hotwired/stimulus"

// Handles two behaviours in the meal form:
//
// 1. When a recipe is selected, read its base servings from the option's
//    data-servings attribute and pre-fill the servings input if it's blank,
//    and show a hint like "Recipe default: 4 servings".
//
// 2. Keep servings at a sensible default until it's typed in by hand: how
//    many people are picked under "Who's eating?", or else — for a shared
//    meal — the family size minus anyone already having their own assigned
//    meal in the chosen slot (slotDataValue, keyed "YYYY-MM-DD|breakfast").
//    New meals follow the date and meal type as they change; edits only
//    recalculate when "Who's eating?" changes.
//
//    When someone picked is still counted in a shared meal planned for the
//    same slot, ask (sharedPrompt) whether to take them out of its servings.
//    The server applies whatever's ticked when the meal saves.
//
// 3. When Snack or Dessert is selected, hide the date field (these are
//    week-level entries; the controller sets date = the first day of the week).
//    Restore it for Breakfast / Lunch / Dinner.

const EXTRA_TYPES = ["snack", "dessert"]

export default class extends Controller {
    static targets = ["dateSection", "dateInput", "servingsInput", "recipeServingsHint",
                       "recurringSection", "recurringCheckbox", "recurringFields", "sharedPrompt"]
    static values  = { familySize: Number, newRecord: Boolean, slotData: Object, originalEaters: Array }

    connect() {
        // Reflect any pre-selected meal type on load (e.g. edit form)
        this.syncDateVisibility()
        if (this.newRecordValue) this.updateServings()
    }

    // Called by the dialog controller after loading the form with a pre-set date/type
    setDate(date, mealType) {
        if (date && this.hasDateInputTarget) {
            this.dateInputTarget.value = date
        }

        if (mealType) {
            const radio = this.element.querySelector(
                `input[name*='meal_name'][value='${mealType.charAt(0).toUpperCase() + mealType.slice(1)}']`
            )
            if (radio) {
                radio.checked = true
                this.syncDateVisibility()
            }
        }
    }

    // Triggered by the recipe <select> changing
    recipeChanged(event) {
        const selected = event.target.selectedOptions[0]
        if (!selected) return

        const recipeServings = parseInt(selected.dataset.servings, 10)
        if (!recipeServings) {
            if (this.hasRecipeServingsHintTarget) this.recipeServingsHintTarget.textContent = ""
            return
        }

        // Pre-fill only when the field is empty (don't override a deliberate edit)
        if (!this.servingsInputTarget.value) {
            this.servingsInputTarget.value = recipeServings
        }

        if (this.hasRecipeServingsHintTarget) {
            this.recipeServingsHintTarget.textContent = `Recipe default: ${recipeServings}`
        }
    }

    servingsEdited() {
        this.servingsTouched = true
    }

    // Triggered by a "Who's eating?" checkbox changing
    eatersChanged() {
        this.updateServings()
        this.renderSharedPrompt()
    }

    // Triggered by the date picker choosing a day
    slotChanged() {
        if (this.newRecordValue) this.updateServings()
        this.renderSharedPrompt()
    }

    // Triggered by any meal_name radio changing
    mealTypeChanged(event) {
        this.syncDateVisibility()
        this.slotChanged()
    }

    // Triggered by the "Make this a recurring meal" checkbox
    recurringToggled() {
        const recurring = this.recurringCheckboxTarget.checked
        this.recurringFieldsTarget.classList.toggle("hidden", !recurring)

        // The recurrence fields have their own "Starts" date, so the plain
        // date field is redundant (and would otherwise fight it for the
        // single meal[date] param) while recurring is on.
        this.dateSectionTarget.classList.toggle("hidden", recurring)
        this.dateInputTarget.required = !recurring
        this.renderSharedPrompt()
    }

    // ── private ──────────────────────────────────────────────────────────────

    updateServings() {
        if (this.servingsTouched || !this.hasServingsInputTarget) return

        const picked = this.element.querySelectorAll("input[name='meal[eater_ids][]']:checked").length
        this.servingsInputTarget.value = picked > 0 ? picked : this.sharedServings()
    }

    // Family size, minus people eating their own assigned meal in this slot.
    sharedServings() {
        const family = this.hasFamilySizeValue ? this.familySizeValue : parseInt(this.servingsInputTarget.value, 10) || 1
        const assigned = this.currentSlot()?.assigned?.length || 0
        return Math.max(family - assigned, 1)
    }

    mealType() {
        return this.element.querySelector("input[name*='meal_name']:checked")?.value?.toLowerCase()
    }

    currentSlot() {
        const date = this.hasDateInputTarget ? this.dateInputTarget.value : ""
        return this.slotDataValue[`${date}|${this.mealType()}`]
    }

    pickedEaters() {
        return [...this.element.querySelectorAll("input[name='meal[eater_ids][]']:checked")].map(input => ({
            id: parseInt(input.value, 10),
            name: input.nextElementSibling?.textContent?.trim() || "They"
        }))
    }

    isRecurring() {
        return this.hasRecurringCheckboxTarget && this.recurringCheckboxTarget.checked
    }

    // Builds (or hides) the "take them out of the shared meal?" question.
    renderSharedPrompt() {
        if (!this.hasSharedPromptTarget) return
        const box = this.sharedPromptTarget
        box.replaceChildren()
        box.classList.add("hidden")

        const type = this.mealType()
        if (!["breakfast", "lunch", "dinner"].includes(type)) return

        const recurring = this.isRecurring()
        const slot = this.currentSlot()
        const alreadyOut = new Set([...(recurring ? [] : slot?.assigned || []), ...this.originalEatersValue])
        const newlyOut = this.pickedEaters().filter(person => !alreadyOut.has(person.id))
        if (newlyOut.length === 0) return

        const names = this.toSentence(newlyOut.map(person => person.name))
        let options

        if (recurring) {
            // Slots aren't known until the rule is saved — offer one blanket yes
            // if this week has any shared meals of this type.
            const anyShared = Object.entries(this.slotDataValue)
                .some(([key, data]) => key.endsWith(`|${type}`) && data.shared.length > 0)
            if (!anyShared) return
            options = [ { name: "meal[drop_shared]", value: "1",
                          label: `Yes, take ${names} out of shared ${type}s already planned this week` } ]
        } else {
            options = (slot?.shared || []).flatMap(shared => {
                const to = Math.max(shared.servings - newlyOut.length, 1)
                if (to === shared.servings) return []
                return [ { name: "meal[drop_shared_meal_ids][]", value: shared.id,
                           label: `Yes, drop ${shared.title} from ${shared.servings} to ${to} servings` } ]
            })
            if (options.length === 0) return
        }

        const question = document.createElement("p")
        question.className = "text-sm text-gray-800 dark:text-gray-200"
        question.textContent = recurring
            ? `${names} will have their own ${type}. Shared ${type}s already planned this week may be counting them.`
            : `${names} will have their own ${type}, but ${options.length === 1 ? "a shared meal" : "shared meals"} already planned then ${options.length === 1 ? "is" : "are"} counting them. Take them out of the servings?`
        box.append(question)

        options.forEach(option => {
            const label = document.createElement("label")
            label.className = "mt-2 flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300 cursor-pointer"
            const input = document.createElement("input")
            input.type = "checkbox"
            input.name = option.name
            input.value = option.value
            input.className = "rounded border-gray-300 dark:border-white/20 text-[#5f734c] focus:ring-[#5f734c]/40"
            const text = document.createElement("span")
            text.textContent = option.label
            label.append(input, text)
            box.append(label)
        })

        box.className = "rounded-lg border border-honey-200 bg-honey-50 px-4 py-3 dark:border-honey-800/50 dark:bg-honey-900/20"
    }

    toSentence(words) {
        if (words.length <= 1) return words.join("")
        return `${words.slice(0, -1).join(", ")} and ${words.at(-1)}`
    }

    syncDateVisibility() {
        const checked = this.element.querySelector("input[name*='meal_name']:checked")
        if (!checked) return

        const isExtra = EXTRA_TYPES.includes(checked.value.toLowerCase())

        if (isExtra) {
            this.dateSectionTarget.classList.add("hidden")
            // Remove required so the form submits without a date;
            // the controller will supply the week's first day.
            this.dateInputTarget.required = false
            this.dateInputTarget.value = ""

            // Recurring meals only make sense for date-scheduled meal types.
            if (this.hasRecurringSectionTarget) {
                this.recurringSectionTarget.classList.add("hidden")
                this.recurringCheckboxTarget.checked = false
                this.recurringFieldsTarget.classList.add("hidden")
            }
        } else {
            if (this.hasRecurringSectionTarget) {
                this.recurringSectionTarget.classList.remove("hidden")
            }

            if (!this.hasRecurringCheckboxTarget || !this.recurringCheckboxTarget.checked) {
                this.dateSectionTarget.classList.remove("hidden")
                this.dateInputTarget.required = true
            }
        }
    }
}