class Meal < ApplicationRecord
  belongs_to :recipe

  CALENDAR_TYPES = %w[breakfast lunch dinner].freeze
  EXTRA_TYPES    = %w[snack dessert].freeze
  ALL_TYPES      = (CALENDAR_TYPES + EXTRA_TYPES).freeze

  validates :meal_name, inclusion: { in: ALL_TYPES.map(&:capitalize) + ALL_TYPES }
  validates :date, presence: true

  # The number of servings being made for this meal instance.
  # Falls back to the recipe's base serving count when not explicitly set.
  def servings
    super || recipe&.servings
  end

  # Ratio of this meal's servings to the recipe's base servings.
  # Used to scale macros for display and ingredient quantities for the grocery list.
  def servings_multiplier
    recipe_servings = recipe&.servings
    return 1.0 if recipe_servings.nil? || recipe_servings.zero?

    # Read the raw DB column via self[] so we don't hit the nil-fallback in
    # the #servings convenience method — a nil column means "use the default",
    # which is exactly 1× the recipe, so we return 1.0 explicitly.
    meal_servings = self[:servings]
    return 1.0 if meal_servings.nil?

    meal_servings.to_f / recipe_servings
  end

  # Scaled macro helpers — these are what the view and grocery list generator should use.
  def scaled_calories
    (recipe.total_calories * servings_multiplier).round
  end

  def scaled_protein
    (recipe.total_protein * servings_multiplier).round(1)
  end

  def scaled_carbs
    (recipe.total_carbs * servings_multiplier).round(1)
  end

  def scaled_fat
    (recipe.total_fat * servings_multiplier).round(1)
  end

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

  def calendar_meal?
    CALENDAR_TYPES.include?(meal_name.downcase)
  end

  def extra_meal?
    EXTRA_TYPES.include?(meal_name.downcase)
  end
end