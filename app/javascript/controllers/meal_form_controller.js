import { Controller } from "@hotwired/stimulus"

// Handles two behaviours in the meal form:
//
// 1. When a recipe is selected, read its base servings from the option's
//    data-servings attribute and pre-fill the servings input if it's blank,
//    and show a hint like "Recipe default: 4 servings".
//
// 2. When Snack or Dessert is selected, hide the date field (these are
//    week-level entries; the controller sets date = Monday of the week).
//    Restore it for Breakfast / Lunch / Dinner.

const EXTRA_TYPES = ["snack", "dessert"]

export default class extends Controller {
    static targets = ["dateSection", "dateInput", "servingsInput", "recipeServingsHint",
                       "recurringSection", "recurringCheckbox", "recurringFields"]

    connect() {
        // Reflect any pre-selected meal type on load (e.g. edit form)
        this.syncDateVisibility()
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
            this.recipeServingsHintTarget.textContent = ""
            return
        }

        // Pre-fill only when the field is empty (don't override a deliberate edit)
        if (!this.servingsInputTarget.value) {
            this.servingsInputTarget.value = recipeServings
        }

        this.recipeServingsHintTarget.textContent = `Recipe default: ${recipeServings}`
    }

    // Triggered by any meal_name radio changing
    mealTypeChanged(event) {
        this.syncDateVisibility()
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
    }

    // ── private ──────────────────────────────────────────────────────────────

    syncDateVisibility() {
        const checked = this.element.querySelector("input[name*='meal_name']:checked")
        if (!checked) return

        const isExtra = EXTRA_TYPES.includes(checked.value.toLowerCase())

        if (isExtra) {
            this.dateSectionTarget.classList.add("hidden")
            // Remove required so the form submits without a date;
            // the controller will supply the week's Monday.
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