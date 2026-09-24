require "application_system_test_case"

# The "create a new ingredient" link swaps a turbo frame on the recipe page,
# so a response without that frame shows Turbo's "Content missing".
class RecipeNewIngredientTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Roast Chicken", visibility: "private", servings: 4)
  end

  test "creating an ingredient from a recipe adds it to that recipe" do
    login_as @user, scope: :user
    visit recipe_url(@recipe)

    click_button "Edit"
    click_link "create a new ingredient"

    assert_no_text "Content missing"
    assert_selector "input[type=submit][value='Create and add Ingredient']"

    fill_in "Ingredient", with: "Smoked paprika"
    fill_in "Amount", with: "2"
    select "tsp", from: "Unit (optional)"
    click_button "Create and add Ingredient"

    assert_text "Roast Chicken"
    assert_text "Smoked paprika"

    line = @recipe.recipe_ingredients.last
    assert_equal "Smoked paprika", line.ingredient.ingredient
    assert_equal 2.0, line.quantity
    assert_equal "tsp", line.unit
  end
end
