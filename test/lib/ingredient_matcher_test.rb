require "test_helper"

class IngredientMatcherTest < ActiveSupport::TestCase
  def parsed(str)
    IngredientParser.new.parse(str)
  end

  test "exact match ignores case and punctuation" do
    Ingredient.create!(ingredient: "Salt")

    result = IngredientMatcher.new.find_or_suggest(parsed("1 tsp salt"))

    assert_equal "exact", result[:method]
    assert_equal "Salt", result[:match].ingredient
  end

  test "exact match uses the same descriptor list the parser uses, even for descriptors the matcher never special-cased on its own" do
    # "boneless" is stripped by IngredientParser::DESCRIPTORS but was not in
    # IngredientMatcher's old, separately-maintained regex — so before
    # unifying normalization, this would have missed and created a
    # duplicate ingredient instead of matching the existing one.
    Ingredient.create!(ingredient: "Boneless Chicken Breast")

    result = IngredientMatcher.new.find_or_suggest(parsed("2 lbs chicken breast"))

    assert_equal "exact", result[:method]
    assert_equal "Boneless chicken breast", result[:match].ingredient
  end

  test "partial match still works once both sides are normalized the same way" do
    Ingredient.create!(ingredient: "Tomato")

    result = IngredientMatcher.new.find_or_suggest(parsed("2 roma tomatoes"))

    assert_equal "partial", result[:method]
    assert_equal "Tomato", result[:match].ingredient
  end

  test "returns no match and a suggested name when nothing matches" do
    Ingredient.create!(ingredient: "Salt")

    result = IngredientMatcher.new.find_or_suggest(parsed("1 cup quinoa"))

    assert_nil result[:match]
    assert_equal "none", result[:method]
    assert_equal "quinoa", result[:suggested_name]
  end

  test "candidates_for ranks existing ingredients by similarity to the search name" do
    Ingredient.create!(ingredient: "Flour")
    Ingredient.create!(ingredient: "All Purpose Flour")
    Ingredient.create!(ingredient: "Brown Sugar")

    candidates = IngredientMatcher.new.candidates_for("flour", limit: 2)

    assert_equal "Flour", candidates.first
    refute_includes candidates, "Brown Sugar"
  end

  test "candidates_for respects the limit" do
    5.times { |i| Ingredient.create!(ingredient: "Ingredient #{i}") }

    candidates = IngredientMatcher.new.candidates_for("ingredient", limit: 3)

    assert_equal 3, candidates.length
  end
end
