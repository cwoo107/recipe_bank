# After the family size changes (edited in settings, or bumped by adding a
# member), the household page offers to carry the change over to meals
# already planned. Only upcoming shared meals are touched — past meals stay as
# eaten, and meals assigned to specific people don't depend on family size.
#
# Servings shift by the difference (3 → 4 adds one) rather than resetting, so
# a meal deliberately planned bigger for leftovers keeps its extra.
class FamilySizeChange
  attr_reader :from, :to

  def initialize(household, from:, to:)
    @household = household
    @from      = from.to_i
    @to        = to.to_i
  end

  def delta = to - from

  # Shared meals from today on. Snacks and desserts are dated the week's first
  # day, so they count for the whole current week.
  def upcoming_meals
    @upcoming_meals ||= @household.meals.where.missing(:meal_assignments)
                                  .where(date: Date.current.beginning_of_week..)
                                  .select { |meal| meal.extra_meal? || meal.date >= Date.current }
  end

  # Shared recurring meals still running. Ones with no servings set already
  # follow the family size (see RecurringMeal#materialize_week!).
  def upcoming_recurring_meals
    @upcoming_recurring_meals ||= @household.recurring_meals.where.missing(:recurring_meal_assignments)
                                            .where.not(servings: nil)
                                            .where("end_date IS NULL OR end_date >= ?", Date.current)
                                            .to_a
  end

  def any?
    delta != 0 && (upcoming_meals.any? || upcoming_recurring_meals.any?)
  end

  def apply!
    return if delta.zero?

    ActiveRecord::Base.transaction do
      upcoming_meals.each { |meal| meal.update!(servings: shifted(meal[:servings])) }
      upcoming_recurring_meals.each { |rule| rule.update_columns(servings: shifted(rule.servings)) }
    end
  end

  # Carried in the flash to the household page.
  def to_flash = { "from" => from, "to" => to }

  private

  def shifted(servings)
    [ (servings || from) + delta, 1 ].max
  end
end
