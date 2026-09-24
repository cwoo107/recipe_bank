require "test_helper"

# A meal built on a recipe with components has to shop for the components too.
class GroceryListComponentsTest < ActionDispatch::IntegrationTest
  setup do
    @user      = users(:one)
    @household = @user.household
    @week      = Date.current.beginning_of_week

    # Fixture meals and lists would otherwise show up in the assertions.
    @household.meals.destroy_all
    @household.grocery_lists.destroy_all

    @chicken = @user.recipes.create!(title: "Chicken", visibility: "private", servings: 4)
    @sauce   = @user.recipes.create!(title: "Lemon Garlic Sauce", visibility: "private", servings: 1)

    @breast = stocked("Chicken breast")
    @cream  = stocked("Cream")
    @chicken.recipe_ingredients.create!(ingredient: @breast, quantity: 400, unit: "g")
    @sauce.recipe_ingredients.create!(ingredient: @cream, quantity: 200, unit: "g")

    sign_in @user
  end

  def stocked(name)
    ing = Ingredient.create!(ingredient: name, family: "produce", unit_price: 4.0, unit_servings: 4)
    ing.create_nutrition_fact!(serving_size: 100, serving_unit: "g", calories: 100,
                               protein: 0, total_fat: 0, total_carb: 0)
    ing
  end

  def plan_meal(servings: nil)
    Meal.create!(recipe: @chicken.reload, user: @user, household: @household,
                 meal_name: "Dinner", date: @week, servings: servings)
  end

  test "without components only the recipe's own ingredients are listed" do
    plan_meal
    post generate_grocery_lists_url, params: { date: @week }

    assert_equal [@breast.id], @household.grocery_lists.pluck(:ingredient_id)
  end

  test "a component's ingredients land on the list too" do
    @chicken.recipe_components.create!(component_recipe: @sauce)
    plan_meal

    post generate_grocery_lists_url, params: { date: @week }

    assert_equal [@breast.id, @cream.id].sort,
                 @household.grocery_lists.pluck(:ingredient_id).sort
  end

  test "a shared ingredient is totalled across the recipe and its component" do
    @sauce.recipe_ingredients.first.update!(ingredient: @breast)
    @chicken.recipe_components.create!(component_recipe: @sauce)
    plan_meal

    post generate_grocery_lists_url, params: { date: @week }

    assert_equal 1, @household.grocery_lists.count, "one line, not one per section"
  end

  test "the component's batch multiplier carries into the amounts" do
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 4)
    plan_meal

    post generate_grocery_lists_url, params: { date: @week }

    cream_units = @household.grocery_lists.find_by(ingredient: @cream).units
    @household.grocery_lists.destroy_all

    @chicken.recipe_components.sole.update!(multiplier: 1)
    post generate_grocery_lists_url, params: { date: @week }

    assert_operator cream_units, :>, @household.grocery_lists.find_by(ingredient: @cream).units
  end
end
