require "test_helper"

class IngredientParserTest < ActiveSupport::TestCase
  def parse(str)
    IngredientParser.new.parse(str)
  end

  test "parses a basic quantity, unit, and name" do
    result = parse("2 cups flour")
    assert_equal 2.0, result[:quantity]
    assert_equal "cup", result[:unit]
    assert_equal "flour", result[:name]
  end

  test "parses a unicode fraction glyph" do
    result = parse("½ cup sugar")
    assert_equal 0.5, result[:quantity]
    assert_equal "cup", result[:unit]
    assert_equal "sugar", result[:name]
  end

  test "parses a mixed number without corrupting the quantity or leaking the unit into the name" do
    result = parse("1 1/2 cups sugar")
    assert_equal 1.5, result[:quantity]
    assert_equal "cup", result[:unit]
    assert_equal "sugar", result[:name]
  end

  test "parses a mixed number using a unicode fraction glyph" do
    result = parse("2 ¾ cups oats")
    assert_equal 2.75, result[:quantity]
    assert_equal "cup", result[:unit]
    assert_equal "oats", result[:name]
  end

  test "parses a standalone ascii fraction with no leading whole number" do
    result = parse("1/2 teaspoon salt")
    assert_equal 0.5, result[:quantity]
    assert_equal "teaspoon", result[:unit]
    assert_equal "salt", result[:name]
  end

  test "averages a quantity range" do
    result = parse("2-3 ripe bananas")
    assert_equal 2.5, result[:quantity]
    assert_equal "bananas", result[:name]
  end

  test "parses an odd fraction that doesn't have a unicode glyph" do
    result = parse("1 3/8 cups flour")
    assert_in_delta 1.375, result[:quantity], 0.001
    assert_equal "cup", result[:unit]
    assert_equal "flour", result[:name]
  end

  test "strips nested parentheticals instead of leaving a stray closing paren" do
    result = parse("2 cups shredded cheese (cheddar or Monterey Jack (or a blend))")
    assert_equal "cheese", result[:name]
  end

  test "strips a simple trailing parenthetical" do
    # "diced" is also stripped separately as a descriptor (see DESCRIPTORS)
    result = parse("1 can diced tomatoes (undrained)")
    assert_equal "tomatoes", result[:name]
  end

  test "strips a leading (qty unit) annotation" do
    result = parse("(4 cups) all purpose flour")
    assert_equal 4.0, result[:quantity]
    assert_equal "cup", result[:unit]
    assert_equal "all purpose flour", result[:name]
  end

  test "strips an inline size annotation" do
    result = parse("1 (15-oz) can black beans")
    assert_equal 1.0, result[:quantity]
    assert_equal "can", result[:unit]
    assert_equal "black beans", result[:name]
  end

  test "handles a compound quantity joined with plus" do
    result = parse("1 tablespoon plus 1 teaspoon kosher salt, divided")
    assert_equal "kosher salt", result[:name]
  end

  test "handles a compound quantity joined with and" do
    result = parse("2 tablespoons and 1 teaspoon olive oil")
    assert_equal "olive oil", result[:name]
  end

  test "does not treat a non-quantity 'and' as a compound quantity" do
    result = parse("2 cups black and white sesame seeds")
    assert_equal "black and white sesame seeds", result[:name]
  end

  test "recognizes capital T as tablespoon" do
    result = parse("2 T butter, softened")
    assert_equal "tablespoon", result[:unit]
    assert_equal "butter", result[:name]
  end

  test "recognizes lowercase t as teaspoon" do
    result = parse("1 t vanilla extract")
    assert_equal "teaspoon", result[:unit]
    assert_equal "vanilla extract", result[:name]
  end

  test "recognizes fl oz as a unit" do
    result = parse("8 fl oz milk")
    assert_equal "fluid ounce", result[:unit]
    assert_equal "milk", result[:name]
  end

  test "recognizes stick as a unit" do
    result = parse("1 stick butter, softened")
    assert_equal "stick", result[:unit]
    assert_equal "butter", result[:name]
  end

  test "recognizes jar, box, and envelope as units" do
    assert_equal "jar", parse("1 jar marinara sauce")[:unit]
    assert_equal "box", parse("1 box spaghetti")[:unit]
    assert_equal "envelope", parse("1 envelope taco seasoning")[:unit]
  end

  test "strips descriptors from the name" do
    result = parse("2 large eggs")
    assert_equal "eggs", result[:name]
  end

  test "search_name strips descriptors and non-alpha characters" do
    result = parse("3 large ripe tomatoes")
    assert_equal "tomatoes", result[:search_name]
  end
end
