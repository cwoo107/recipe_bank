module Dashboard
  class GroceriesSection < Section
    KEY   = "groceries".freeze
    LABEL = "Grocery list".freeze
    ICON  = "groceries".freeze

    def meals_planned?
      household.meals.where(date: week_range).exists?
    end

    def grocery_lists_this_week
      @grocery_lists_this_week ||= household.grocery_lists
                                             .where(week_of: week_start)
                                             .includes(:ingredient)
    end

    def item_count
      grocery_lists_this_week.count
    end

    def estimated_subtotal
      grocery_lists_this_week.sum do |gl|
        next 0 unless gl.ingredient&.unit_price
        gl.units.to_i * gl.ingredient.unit_price
      end
    end

    def empty?
      grocery_lists_this_week.none?
    end

    def summary_line
      "#{item_count} item#{'s' unless item_count == 1}, ~$#{format('%.2f', estimated_subtotal)}"
    end

    def empty_headline
      "Grocery list"
    end

    def empty_body
      if meals_planned?
        "Nothing planned yet this week."
      else
        "Plan your meals first, then generate a grocery list."
      end
    end

    def cta_label
      meals_planned? ? "Build grocery list" : "Plan meals"
    end

    def cta_path
      meals_planned? ? step_path : plan_week_step_path(section: "meals")
    end
  end
end
