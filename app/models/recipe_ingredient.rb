class RecipeIngredient < ApplicationRecord
  belongs_to :recipe
  belongs_to :ingredient

  # Recipes only draw on their own household's ingredient library, so one
  # household deleting or editing an ingredient can't reach anyone else's
  # recipes. Checked only when the ingredient changes, so lines saved before
  # ingredients were per-household can still have their amounts edited.
  validate :ingredient_in_recipe_household, if: :will_save_change_to_ingredient_id?

  # The unit picker shown on the recipe page. Every option here is one
  # Recipe#convert_to_grams can weigh, so the macro maths keeps working
  # whichever the user picks.
  #
  # A blank unit is deliberately allowed — "1 chicken breast" has a quantity
  # but no unit — and is counted as a piece when working out macros.
  UNIT_GROUPS = {
    "Volume" => ["tsp", "tbsp", "fl oz", "cup", "pint", "quart", "ml", "liter"],
    "Weight" => ["oz", "lb", "g", "kg"],
    "Count"  => ["piece", "slice", "clove", "pinch", "dash"]
  }.freeze

  UNITS = UNIT_GROUPS.values.flatten.freeze

  private

  def ingredient_in_recipe_household
    return if ingredient.nil? || recipe.nil?
    return if ingredient.household_id.present? && ingredient.household_id == recipe.user&.household&.id

    errors.add(:ingredient, "must be one of your household's ingredients")
  end
end
