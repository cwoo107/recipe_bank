require "test_helper"

class UnitNormalizerTest < ActiveSupport::TestCase
  def normalized(unit) = UnitNormalizer.call(unit).unit

  test "however it's written, a unit comes out the picker's way" do
    {
      "Tbsp" => "tbsp", "tbsp." => "tbsp", "Tablespoons" => "tbsp", "TBS" => "tbsp",
      "Tsp" => "tsp", "teaspoon" => "tsp", "Cups" => "cup", "Grams" => "g", "gram" => "g",
      "ounce" => "oz", "Pounds" => "lb", "lbs" => "lb", "Fl. Oz." => "fl oz", "fluid ounces" => "fl oz",
      "litre" => "liter", "L" => "liter", "ML" => "ml", "cloves" => "clove", "Slices" => "slice",
      "pcs" => "piece", " pinches " => "pinch"
    }.each { |written, unit| assert_equal unit, normalized(written), written }
  end

  test "capital T is a tablespoon and small t a teaspoon" do
    assert_equal "tbsp", normalized("T")
    assert_equal "tsp", normalized("t")
  end

  test "count words and blanks mean no unit" do
    [ "whole", "Each", "ea.", "", "  ", nil ].each { |written| assert_nil normalized(written), written.inspect }
  end

  test "units the picker doesn't offer are kept, with a note" do
    result = UnitNormalizer.call(" can ")
    assert_equal "can", result.unit
    assert_not result.recognized?
    assert_match "isn't one of the recipe page's units", result.notes.first

    assert_equal "C", normalized("C"), "not guessed as a cup"
  end

  test "every unit it produces is one the picker offers" do
    assert_empty UnitNormalizer::ALIASES.keys - RecipeIngredient::UNITS
    assert_empty RecipeIngredient::UNITS - UnitNormalizer::ALIASES.keys, "every picker unit has its spellings listed"
  end

  test "units are tidied when recipe lines and nutrition facts are saved" do
    recipe = users(:one).recipes.create!(title: "Pancakes")
    line = recipe.recipe_ingredients.create!(ingredient: households(:one).ingredients.create!(ingredient: "Flour"),
                                             quantity: 2, unit: "Tablespoons")
    assert_equal "tbsp", line.unit

    fact = line.ingredient.create_nutrition_fact!(serving_size: 1, serving_unit: "Cups", calories: 400)
    assert_equal "cup", fact.serving_unit
  end

  test "lines saved without touching their unit keep it as it was" do
    recipe = users(:one).recipes.create!(title: "Pancakes")
    line = recipe.recipe_ingredients.create!(ingredient: households(:one).ingredients.create!(ingredient: "Flour"), quantity: 2)
    line.update_column(:unit, "teaspoon")

    line.update!(quantity: 3)
    assert_equal "teaspoon", line.reload.unit, "left for the audit to tidy"
  end
end
