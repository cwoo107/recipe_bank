# Calories, macros and cost for a week of meals — for the whole household, or
# for one member (their share of each meal, see Meal#share_for). Feeds the
# meals page's Week summary panel and the household member summary page.
class MealWeekStats
  CHART_COLORS = [
    "oklch(71.1% 0.019 323.02)",
    "oklch(85% 0.08 95)",
    "oklch(75% 0.06 45)"
  ].freeze

  attr_reader :member

  def initialize(meals, member: nil)
    @meals  = meals
    @member = member
  end

  # Each meal this person ate some of, with their share of its totals —
  # in eating order: by day, then breakfast, lunch, dinner, snack, dessert.
  # Note-only meals have nothing to count, so they're left out (though they
  # still take their eaters out of the slot's shared meals, below).
  def rows
    @rows ||= @meals.sort_by { |meal| [ meal.date, Meal::ALL_TYPES.index(meal.meal_name.downcase) || Meal::ALL_TYPES.size ] }.filter_map do |meal|
      next if meal.note_only?

      share = meal.share_for(member, excluded_ids: assigned_in_slot.fetch(meal.slot, []))
      next if share.zero?

      {
        meal:      meal,
        name:      meal.title,
        meal_name: meal.meal_name,
        date:      meal.date,
        share:     share,
        calories:  meal.scaled_calories * share,
        protein:   meal.scaled_protein  * share,
        carbs:     meal.scaled_carbs    * share,
        fat:       meal.scaled_fat      * share,
        cost:      meal.total_cost      * share
      }
    end
  end

  # Who has their own assigned meal in each breakfast/lunch/dinner slot —
  # they're left out of that slot's shared (unassigned) meals.
  def assigned_in_slot
    @assigned_in_slot ||= @meals.select(&:slot).group_by(&:slot).transform_values do |slot_meals|
      slot_meals.flat_map(&:eater_ids_assigned).uniq
    end
  end

  def to_h
    total = ->(key) { rows.sum { |r| r[key] } }
    protein, carbs, fat = total.(:protein), total.(:carbs), total.(:fat)
    calories, cost      = total.(:calories), total.(:cost)

    {
      member:            member,
      total_protein:     protein.round(1),
      total_carbs:       carbs.round(1),
      total_fat:         fat.round(1),
      total_calories:    calories.round,
      total_cost:        cost.round(2),
      # "per_serv" is historical naming — these are per-day averages.
      per_serv_protein:  (protein  / 7.0).round(1),
      per_serv_carbs:    (carbs    / 7.0).round(1),
      per_serv_fat:      (fat      / 7.0).round(1),
      per_serv_calories: (calories / 7.0).round,
      per_serv_cost:     (cost     / 7.0).round(2),
      meal_count:        rows.size,
      chart_data: {
        labels: [ "Protein #{protein.round(1)}g", "Carbs #{carbs.round(1)}g", "Fat #{fat.round(1)}g" ],
        datasets: [ {
          data:            [ protein.round(1), carbs.round(1), fat.round(1) ],
          backgroundColor: CHART_COLORS,
          borderWidth:     2
        } ]
      },
      meals: rows
    }
  end
end
