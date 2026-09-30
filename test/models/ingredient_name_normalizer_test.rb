require "test_helper"

class IngredientNameNormalizerTest < ActiveSupport::TestCase
  # The mangled names recipe imports actually produced.
  {
    ". finely parmesan"                    => "Parmesan",
    ". finely sun- tomatoes"               => "Tomatoes",
    ". thyme leaves"                       => "Thyme",
    "/8 tsp black pepper"                  => "Black pepper",
    "Caster sugar / superfine sugar"       => "Caster sugar",
    "Kosher salt and freshly black pepper" => "Kosher salt and black pepper",
    "See brown sugar alternative"          => "Brown sugar",
    "Vegetable or canola oil"              => "Vegetable oil",
    ". red pepper flakes"                  => "Red pepper flakes",
    "Roughly parsley"                      => "Parsley",
    "Torn basil"                           => "Basil",
    "2 cloves garlic, minced"              => "Garlic",
    "Salt, to taste"                       => "Salt",
    "Extra virgin olive oil (optional)"    => "Extra virgin olive oil"
  }.each do |mangled, clean|
    test "cleans #{mangled.inspect} to #{clean.inspect}" do
      assert_equal clean, IngredientNameNormalizer.call(mangled).name
    end
  end

  # Words that look like prep or units but change what you'd buy.
  [ "Bay leaves", "Curry leaves", "Cloves", "Half and half", "Toasted sesame oil", "Ground beef",
    "Smoked paprika", "Crushed tomatoes", "Fresh garlic", "All-purpose flour", "Low-sodium chicken broth" ].each do |name|
    test "leaves #{name.inspect} alone" do
      result = IngredientNameNormalizer.call(name)
      assert_equal name, result.name
      assert_not result.changed_from?(name)
    end
  end

  test "notes what a person should double-check" do
    assert_match(/amount in its name/, IngredientNameNormalizer.call("/8 tsp black pepper").notes.join)
    assert_match(/kept the first/, IngredientNameNormalizer.call("Vegetable or canola oil").notes.join)
    assert_match(/two ingredients in one/, IngredientNameNormalizer.call("Kosher salt and freshly black pepper").notes.join)
    assert_match(/cross-reference/, IngredientNameNormalizer.call("See brown sugar alternative").notes.join)
    assert_match(/cut-off word/, IngredientNameNormalizer.call(". finely sun- tomatoes").notes.join)
    assert_empty IngredientNameNormalizer.call(". finely parmesan").notes
  end

  test "keeps the original when nothing is left after cleaning" do
    result = IngredientNameNormalizer.call(". finely")
    assert_equal ". finely", result.name
    assert_match(/by hand/, result.notes.join)
  end
end
