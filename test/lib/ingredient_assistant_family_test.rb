require "test_helper"

# The offline fallback for classifying ingredient families (see
# IngredientAssistant#guess_family_programmatically).
class IngredientAssistantFamilyTest < ActiveSupport::TestCase
  setup { @ai = IngredientAssistant.new }

  {
    "frozen peas"          => "frozen",
    "vanilla ice cream"    => "frozen",
    "chicken broth"        => "canned",
    "diced tomatoes"       => "canned",
    "soy sauce"            => "condiments",
    "apple cider vinegar"  => "condiments",
    "dijon mustard"        => "condiments",
    "brown sugar"          => "baking",
    "vanilla extract"      => "baking",
    "baking powder"        => "baking",
    "walnuts"              => "nuts",
    "peanut butter"        => "nuts",
    "coffee"               => "beverages",
    "chicken breast"       => "protein",
    "black beans"          => "protein",
    "cumin"                => "spices",
    "cheddar cheese"       => "dairy",
    "olive oil"            => "fat",
    "spaghetti"            => "grain",
    "carrot"               => "produce",
    "paper towels"         => "grocery"
  }.each do |name, family|
    test "guesses #{family} for #{name}" do
      assert_equal family, @ai.send(:guess_family_programmatically, name)
    end
  end

  test "every guess is a known family" do
    assert_includes Ingredient::FAMILIES.keys, @ai.send(:guess_family_programmatically, "mystery item")
  end
end
