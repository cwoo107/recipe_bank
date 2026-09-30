require "test_helper"

# Servings is optional on a recipe. A blank value used to leave Meal#servings
# nil (500s on the meal plan), hide the nutrition chart, and planned meals
# blocked the recipe from being deleted.
class RecipeWithoutServingsTest < ActiveSupport::TestCase
  setup do
    @user      = users(:one)
    @household = households(:one)
    @recipe    = @user.recipes.create!(title: "No Servings", visibility: "private", servings: nil)

    ing = Ingredient.create!(household: households(:one), ingredient: "Rice", family: "produce")
    ing.create_nutrition_fact!(serving_size: 100, serving_unit: "g", calories: 100,
                               protein: 10, total_fat: 0, total_carb: 0)
    @recipe.recipe_ingredients.create!(ingredient: ing, quantity: 200, unit: "g")
  end

  def plan_meal(servings: nil)
    @household.meals.create!(user: @user, recipe: @recipe, meal_name: "Lunch",
                             date: Date.current, servings: servings)
  end

  test "recipe per-serving macros treat the whole recipe as one serving" do
    assert_equal 200, @recipe.calories_per_serving
    assert_equal 20.0, @recipe.protein_per_serving
  end

  test "a meal of it falls back to one serving" do
    meal = plan_meal

    assert_equal 1, meal.servings
    assert_equal 200, meal.calories_per_serving
    assert_equal 20.0, meal.protein_per_serving
    assert_equal 0, meal.cost_per_serving
  end

  test "it can be deleted once it's on the meal plan" do
    plan_meal
    recurring = RecurringMeal.create!(household: @household, user: @user, recipe: @recipe,
                                      meal_name: "Dinner", pattern_type: "interval",
                                      interval_days: 1, start_date: Date.current, end_type: "week")
    recurring.materialize_week!(Date.current.beginning_of_week)

    assert_difference -> { Recipe.count } => -1, -> { RecurringMeal.count } => -1 do
      @recipe.destroy!
    end
    assert_equal 0, Meal.where(recipe_id: @recipe.id).count
  end
end
