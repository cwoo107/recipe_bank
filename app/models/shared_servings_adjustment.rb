# When someone is newly assigned their own meal, any shared (unassigned) meal
# already planned in that same slot was probably counting them in its
# servings. The meal form asks whether to take them out; this works out the
# new servings for those shared meals and applies the ones confirmed.
#
# Built from [meal, newly_assigned_member_ids] pairs — one for a single meal,
# several for a recurring rule's generated week.
class SharedServingsAdjustment
  def initialize(household, assignments)
    @household   = household
    @assignments = assignments
  end

  # { shared_meal_id => new servings } for every shared meal counting someone
  # who's now eating their own meal. One serving comes off per person, never
  # below 1.
  def adjustments
    @adjustments ||= begin
      drops = Hash.new(0)
      meals = {}

      @assignments.each do |meal, new_ids|
        next unless meal.calendar_meal?

        # Anyone already eating another assigned meal in this slot wasn't being
        # counted in the shared meals anyway.
        newly_out = new_ids - @household.assigned_member_ids_in_slot(meal.date, meal.meal_name, except: meal)
        next if newly_out.empty?

        shared_meals_in_slot(meal).each do |shared|
          meals[shared.id] = shared
          drops[shared.id] += newly_out.size
        end
      end

      drops.to_h { |id, drop| [ id, [ meals[id].servings - drop, 1 ].max ] }
           .reject { |id, servings| servings == meals[id].servings }
    end
  end

  # Applies the adjustments (limited to `only_ids` when given — the shared
  # meals the person said yes to). Returns the meals that changed.
  def apply!(only_ids: nil)
    targets = only_ids ? adjustments.slice(*only_ids.map(&:to_i)) : adjustments
    @household.meals.where(id: targets.keys).each { |meal| meal.update!(servings: targets[meal.id]) }
  end

  private

  def shared_meals_in_slot(meal)
    @household.meals
              .where(date: meal.date).where("LOWER(meal_name) = ?", meal.meal_name.downcase)
              .where.not(id: meal.id)
              .where.missing(:meal_assignments)
  end
end
