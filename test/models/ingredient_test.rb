require "test_helper"

class IngredientTest < ActiveSupport::TestCase
  test "capitalizes the ingredient name on save" do
    ingredient = Ingredient.create!(ingredient: "extra virgin olive OIL")
    assert_equal "Extra virgin olive oil", ingredient.ingredient
  end

  test "strips surrounding whitespace while capitalizing" do
    ingredient = Ingredient.create!(ingredient: "  chicken breast  ")
    assert_equal "Chicken breast", ingredient.ingredient
  end
end
