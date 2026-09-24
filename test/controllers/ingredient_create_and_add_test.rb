require "test_helper"

# "Create and add Ingredient" — the compact form reached from a recipe's edit
# mode, which saves the ingredient and its recipe line together.
class IngredientCreateAndAddTest < ActionDispatch::IntegrationTest
  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Roast Chicken", visibility: "private", servings: 4)
    sign_in @user
  end

  test "the form asks only for what the recipe line needs" do
    get new_ingredient_url(recipe_id: @recipe.id)

    assert_response :success
    assert_select "input[name=?]", "ingredient[ingredient]"
    assert_select "select[name=?]", "ingredient[family]"
    assert_select "input[name=?]", "recipe_ingredient[quantity]"
    assert_select "select[name=?]", "recipe_ingredient[unit]"
    assert_select "input[type=submit][value=?]", "Create and add Ingredient"
  end

  test "the response carries the frame the recipe page's link targets" do
    # recipes/_new_ingredient links here from inside <turbo-frame
    # id="new_ingredient">, so a response without it is "content missing".
    get new_recipe_link_target

    assert_response :success
    assert_select "turbo-frame#new_ingredient input[type=submit][value=?]",
                  "Create and add Ingredient"
  end

  test "the recipe page really does link from inside that frame" do
    get recipe_url(@recipe)

    assert_select "turbo-frame#new_ingredient a[href=?]", new_recipe_link_target
  end

  test "a rejected submission still comes back inside the frame" do
    post ingredients_url, params: {
      recipe_id: @recipe.id,
      ingredient: { ingredient: "" },
      recipe_ingredient: { quantity: 2 }
    }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#new_ingredient"
  end

  test "the fields the AI fills in are kept off the form" do
    get new_ingredient_url(recipe_id: @recipe.id)

    assert_select "input[name=?]", "ingredient[unit_price]", count: 0
    assert_select "input[name=?]", "ingredient[unit_servings]", count: 0
    assert_select "input[name=?]", "ingredient[calories]", count: 0
  end

  test "the standalone ingredient form is untouched" do
    get new_ingredient_url

    assert_response :success
    assert_select "input[type=submit][value=?]", "Create Ingredient"
    assert_select "input[name=?]", "ingredient[unit_price]"
    assert_select "input[name=?]", "recipe_ingredient[quantity]", count: 0
  end

  test "submitting creates the ingredient and puts it on the recipe" do
    assert_difference(["Ingredient.count", "RecipeIngredient.count"], 1) do
      post ingredients_url, params: {
        recipe_id: @recipe.id,
        ingredient: { ingredient: "smoked paprika", family: "spices" },
        recipe_ingredient: { quantity: 2, unit: "tsp" }
      }
    end

    assert_redirected_to recipe_url(@recipe)

    line = @recipe.recipe_ingredients.last
    assert_equal "Smoked paprika", line.ingredient.ingredient
    assert_equal "spices", line.ingredient.family
    assert_equal @user, line.ingredient.created_by
    assert_equal 2.0, line.quantity
    assert_equal "tsp", line.unit
  end

  test "the unit stays optional for things counted whole" do
    post ingredients_url, params: {
      recipe_id: @recipe.id,
      ingredient: { ingredient: "chicken breast" },
      recipe_ingredient: { quantity: 1, unit: "" }
    }

    line = @recipe.recipe_ingredients.last
    assert_nil line.unit.presence
    assert_nil line.ingredient.family.presence, "family is left for the AI to work out"
  end

  test "submitting from the recipe page streams the line back in place" do
    post ingredients_url, params: {
      recipe_id: @recipe.id,
      ingredient: { ingredient: "smoked paprika" },
      recipe_ingredient: { quantity: 2, unit: "tsp" }
    }, as: :turbo_stream

    assert_response :success
    assert_match 'target="recipe_ingredients_section"', response.body
    assert_match 'target="new_ingredient"', response.body
    assert_match 'target="macros_chart"', response.body
    assert_match "Smoked paprika", response.body
  end

  test "enrichment is queued for the new ingredient" do
    assert_enqueued_with(job: IngredientEnrichmentJob) do
      post ingredients_url, params: {
        recipe_id: @recipe.id,
        ingredient: { ingredient: "smoked paprika" },
        recipe_ingredient: { quantity: 2, unit: "tsp" }
      }
    end
  end

  test "a nameless ingredient is rejected without leaving a stray recipe line" do
    assert_no_difference(["Ingredient.count", "RecipeIngredient.count"]) do
      post ingredients_url, params: {
        recipe_id: @recipe.id,
        ingredient: { ingredient: "" },
        recipe_ingredient: { quantity: 2, unit: "tsp" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "input[type=submit][value=?]", "Create and add Ingredient"
  end

  test "ingredients can't be added to someone else's recipe" do
    theirs = users(:three).recipes.create!(title: "Theirs", visibility: "public")

    assert_no_difference("RecipeIngredient.count") do
      post ingredients_url, params: {
        recipe_id: theirs.id,
        ingredient: { ingredient: "smoked paprika" },
        recipe_ingredient: { quantity: 1 }
      }
    end
    assert_response :not_found
  end

  private

  def new_recipe_link_target
    new_ingredient_path(recipe_id: @recipe.id)
  end
end
