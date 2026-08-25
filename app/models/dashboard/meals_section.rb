module Dashboard
  class MealsSection < Section
    KEY   = "meals".freeze
    LABEL = "Meals".freeze
    ICON  = "meals".freeze

    DAYS_IN_WEEK = 7

    def meals_this_week
      @meals_this_week ||= household.meals
                                     .where(date: week_range)
                                     .includes(:recipe)
                                     .order(:date)
    end

    def dinners_planned
      meals_this_week.count { |m| m.meal_name.downcase == "dinner" }
    end

    def empty?
      meals_this_week.none?
    end

    def summary_line
      "#{dinners_planned} of #{DAYS_IN_WEEK} dinners planned"
    end

    def detail_line
      upcoming = meals_this_week.select { |m| m.date >= Date.current }.first(2)
      return nil if upcoming.empty?

      upcoming.map { |m| "#{m.meal_name} — #{m.recipe.title}" }.join(", ")
    end

    def empty_headline = "Meals"
    def empty_body     = "Nothing planned yet this week."
    def cta_label      = "Plan meals"
  end
end
