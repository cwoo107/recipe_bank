# What a grocery list line is for — the hover on its "used in N meals":
# which recipes need it and how many times each is planned that week, and
# how much of it they need in all.
#
# The total is given in the unit the recipes use most (Flour in three
# recipes by the cup and one by the tbsp comes out in cups), converting
# whatever can be — volumes to volumes, weights to weights. Anything that
# can't (cloves, a count) gets its own amount alongside.
#
#   uses = GroceryList::Breakdown.uses_by_ingredient(meals)
#   breakdown = grocery_list.breakdown(uses)
#   breakdown.recipes  # => [[#<Recipe Pancakes>, 2], [#<Recipe Muffins>, 1]]
#   breakdown.amounts  # => [[3.25, "cup"], [2.0, "piece"]]
class GroceryList::Breakdown
  # One meal's need for one ingredient: the recipe line (components
  # included) scaled to the meal's servings.
  Use = Struct.new(:meal_id, :recipe, :quantity, :unit, keyword_init: true)

  # How much of a base unit each unit is.
  VOLUME_ML = { "tsp" => 4.92892, "tbsp" => 14.7868, "fl oz" => 29.5735, "cup" => 236.588,
                "pint" => 473.176, "quart" => 946.353, "ml" => 1.0, "liter" => 1000.0 }.freeze
  WEIGHT_G  = { "g" => 1.0, "kg" => 1000.0, "oz" => 28.3495, "lb" => 453.592 }.freeze

  # Every recipe-planned meal's ingredient lines, by ingredient id — built
  # once for a whole list (GroceryListsController#index) rather than per row.
  def self.uses_by_ingredient(meals)
    meals.each_with_object(Hash.new { |hash, id| hash[id] = [] }) do |meal, uses|
      next unless meal.recipe

      multiplier = meal.servings_multiplier
      meal.recipe.all_ingredients.each do |line|
        next unless line.ingredient_id

        uses[line.ingredient_id] << Use.new(meal_id: meal.id, recipe: meal.recipe,
                                            quantity: line.quantity.to_f * multiplier,
                                            unit: UnitNormalizer.call(line.unit).unit)
      end
    end
  end

  def initialize(uses)
    @uses = uses
  end

  def any? = @uses.any?

  # [[recipe, meals that week]], the most planned first.
  def recipes
    @uses.group_by(&:recipe)
         .map { |recipe, uses| [ recipe, uses.map(&:meal_id).uniq.size ] }
         .sort_by { |recipe, times| [ -times, recipe.title.to_s.downcase ] }
  end

  # [[quantity, unit]] — the most used unit first, with everything that
  # converts to it folded in; nil unit is a plain count.
  def amounts
    # Units by how many lines use them (ties: the one seen first).
    ranked = @uses.map(&:unit).tally.each_with_index
                  .sort_by { |(_, count), index| [ -count, index ] }
                  .map { |(unit, _), _| unit }

    # Each unit adds into the first, more used unit it converts to.
    target = {}
    ranked.each_with_index do |unit, index|
      target[unit] = ranked.first(index).find { |other| target[other] == other && convertible?(unit, other) } || unit
    end

    totals = Hash.new(0.0)
    @uses.each { |use| totals[target[use.unit]] += convert(use.quantity, use.unit, target[use.unit]) }

    ranked.filter_map { |unit| [ totals[unit], unit ] if totals.key?(unit) && totals[unit].positive? }
  end

  private

  def convertible?(from, to)
    from == to || [ VOLUME_ML, WEIGHT_G ].any? { |table| table.key?(from) && table.key?(to) }
  end

  def convert(quantity, from, to)
    return quantity if from == to

    table = VOLUME_ML.key?(from) ? VOLUME_ML : WEIGHT_G
    quantity * table.fetch(from) / table.fetch(to)
  end
end
