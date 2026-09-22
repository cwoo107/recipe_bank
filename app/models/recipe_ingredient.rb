class RecipeIngredient < ApplicationRecord
  belongs_to :recipe
  belongs_to :ingredient

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
end
