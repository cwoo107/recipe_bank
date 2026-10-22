require "test_helper"

class GroceryList::BreakdownTest < ActiveSupport::TestCase
  setup do
    @user      = users(:one)
    @household = @user.household
    @week      = Date.current.beginning_of_week
    @flour     = @household.ingredients.create!(ingredient: "Breakdown flour", family: "baking")
  end

  def recipe(title, quantity, unit, servings: 4)
    @user.recipes.create!(title:, servings:, visibility: "private").tap do |recipe|
      recipe.recipe_ingredients.create!(ingredient: @flour, quantity:, unit:)
    end
  end

  def plan(recipe, day: 0, servings: nil)
    @household.meals.create!(user: @user, recipe:, meal_name: "Dinner", date: @week + day, servings:)
  end

  def breakdown(meals)
    line = @household.grocery_lists.create!(user: @user, ingredient: @flour, units: 1, week_of: @week, meal_ids: meals.map(&:id))
    line.breakdown
  end

  test "totals in the unit most recipes use, converting the rest" do
    pancakes = recipe("Pancakes", 2, "cup")
    muffins  = recipe("Muffins", 1, "cup")
    gravy    = recipe("Gravy", 4, "tbsp")
    meals = [ plan(pancakes), plan(pancakes, day: 1), plan(muffins), plan(gravy) ]

    result = breakdown(meals)

    assert_equal [ [ "Pancakes", 2 ], [ "Gravy", 1 ], [ "Muffins", 1 ] ], result.recipes.map { |r, n| [ r.title, n ] }
    (quantity, unit), *rest = result.amounts
    assert_equal "cup", unit
    assert_in_delta 5.25, quantity, 0.01 # 2 + 2 + 1 cups, and 4 tbsp is ¼ cup
    assert_empty rest
  end

  test "scales each meal by its servings, and keeps units that don't convert apart" do
    bread = recipe("Bread", 500, "g", servings: 4)
    rolls = recipe("Rolls", 3, "piece")
    meals = [ plan(bread, servings: 8), plan(rolls) ]

    amounts = breakdown(meals).amounts

    assert_equal [ [ 1000.0, "g" ], [ 3.0, "piece" ] ], amounts.sort_by { |_, unit| unit }
  end

  test "a unit written longhand counts as the same unit" do
    a = recipe("A", 1, "cup")
    b = recipe("B", 1, "Cups")
    c = recipe("C", 3, "tsp")

    amounts = breakdown([ plan(a), plan(b), plan(c) ]).amounts

    assert_equal "cup", amounts.first.last
    assert_in_delta 2.0625, amounts.first.first, 0.001
  end

  test "a note or a line with no meals has nothing to break down" do
    assert_not @household.grocery_lists.create!(user: @user, note: "Candles", week_of: @week).breakdown.any?
    assert_not @household.grocery_lists.create!(user: @user, ingredient: @flour, units: 1, week_of: @week).breakdown.any?
  end
end
