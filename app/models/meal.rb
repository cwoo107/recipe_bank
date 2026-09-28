class Meal < ApplicationRecord
  belongs_to :recipe
  belongs_to :user
  belongs_to :household
  belongs_to :recurring_meal, optional: true

  has_one :recurring_meal_occurrence, dependent: :nullify

  has_many :meal_assignments, dependent: :destroy
  has_many :eaters, through: :meal_assignments, source: :household_member

  CALENDAR_TYPES = %w[breakfast lunch dinner].freeze
  EXTRA_TYPES    = %w[snack dessert].freeze
  ALL_TYPES      = (CALENDAR_TYPES + EXTRA_TYPES).freeze

  validates :meal_name, inclusion: { in: ALL_TYPES.map(&:capitalize) + ALL_TYPES }
  validates :date, presence: true

  # Falls back to the recipe's servings, then to 1 — recipes may leave
  # servings blank, and every per-serving figure below divides by this.
  def servings
    super || recipe&.servings || 1
  end

  def servings_multiplier
    recipe_servings = recipe&.servings
    return 1.0 if recipe_servings.nil? || recipe_servings.zero?
    meal_servings = self[:servings]
    return 1.0 if meal_servings.nil?
    meal_servings.to_f / recipe_servings
  end

  def scaled_calories  = (recipe.total_calories * servings_multiplier).round
  def scaled_protein   = (recipe.total_protein  * servings_multiplier).round(1)
  def scaled_carbs     = (recipe.total_carbs    * servings_multiplier).round(1)
  def scaled_fat       = (recipe.total_fat      * servings_multiplier).round(1)

  def calories_per_serving
    return 0 if servings.zero?
    (scaled_calories.to_f / servings).round
  end

  def protein_per_serving
    return 0 if servings.zero?
    (scaled_protein / servings).round(1)
  end

  def carbs_per_serving
    return 0 if servings.zero?
    (scaled_carbs / servings).round(1)
  end

  def fat_per_serving
    return 0 if servings.zero?
    (scaled_fat / servings).round(1)
  end

  def assigned? = meal_assignments.any?

  def eater_ids_assigned = meal_assignments.map(&:household_member_id)

  # Breakfast, lunch and dinner on a given day are each one "slot". (Snacks
  # and desserts are week-level extras, so they aren't slotted.)
  def slot = calendar_meal? ? [ date, meal_name.downcase ] : nil

  # The fraction of this meal `member` ate. Assigned meals split evenly among
  # the people assigned (none for anyone else). Unassigned meals are shared by
  # the family, minus anyone eating their own assigned meal in the same slot
  # (`excluded_ids`, see MealWeekStats) — so someone having eggs instead of
  # the family's pancakes gets none of the pancakes, and the rest split them.
  # nil member means the whole household (all of it).
  def share_for(member, excluded_ids: [])
    return 1.0 if member.nil?

    eater_ids = eater_ids_assigned
    if eater_ids.any?
      eater_ids.include?(member.id) ? 1.0 / eater_ids.size : 0.0
    elsif excluded_ids.include?(member.id)
      0.0
    else
      1.0 / [ household.family_size - excluded_ids.size, 1 ].max
    end
  end

  def calendar_meal? = CALENDAR_TYPES.include?(meal_name.downcase)
  def extra_meal?    = EXTRA_TYPES.include?(meal_name.downcase)

  # Counts component recipes too — all_ingredients already folds in their
  # batch multipliers, and the meal's own servings multiplier sits on top.
  def total_cost
    recipe.all_ingredients.sum do |line|
      ingredient = line.ingredient
      next 0 unless ingredient&.unit_price.present? && ingredient.unit_servings.present? && ingredient.unit_servings > 0

      fraction_of_unit = 1.0 / ingredient.unit_servings
      ingredient.unit_price * fraction_of_unit * servings_multiplier
    end
  end

  def cost_per_serving
    return 0 if servings.zero?
    total_cost / servings
  end
end