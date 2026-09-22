require "test_helper"

# Inline quantity/unit editing from the recipe page's edit mode.
class RecipeIngredientEditingTest < ActionDispatch::IntegrationTest
  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Roast Chicken", visibility: "private", servings: 4)
    @breast = Ingredient.create!(ingredient: "Chicken breast", family: "protein")
    @line   = @recipe.recipe_ingredients.create!(ingredient: @breast, quantity: 2.0, unit: "lb")

    sign_in @user
  end

  test "edit mode offers a quantity field and a unit picker for each ingredient" do
    get recipe_url(@recipe)

    assert_response :success
    # Both halves ship with the row; edit mode swaps which one is visible.
    assert_select "[data-edit-mode-target=viewOnlyItems] [data-serving-scaler-target=quantity]"
    # The family pill is view-only too, so the amount form gets the width.
    assert_select "td[data-edit-mode-target=viewOnlyItems]", text: "Protein"
    assert_select "input[name=?][value=?]", "recipe_ingredient[quantity]", "2.0"
    assert_select "select[name=?]", "recipe_ingredient[unit]" do
      assert_select "option[selected][value=?]", "lb"
      assert_select "optgroup[label=?]", "Volume"
      assert_select "optgroup[label=?]", "Weight"
      assert_select "optgroup[label=?]", "Count"
      assert_select "option[value='']" # the unit can be cleared
    end
  end

  test "the picker keeps a legacy free-text unit rather than rewriting it" do
    @line.update!(unit: "tablespoons")

    get recipe_url(@recipe)

    assert_select "optgroup[label=?]", "Current" do
      assert_select "option[selected][value=?]", "tablespoons"
    end
  end

  test "updating quantity and unit re-renders the row and the macros chart" do
    patch recipe_recipe_ingredient_url(@recipe, @line),
          params: { recipe_ingredient: { quantity: 1.5, unit: "kg" } },
          as: :turbo_stream

    assert_response :success
    @line.reload
    assert_equal 1.5, @line.quantity
    assert_equal "kg", @line.unit

    assert_match "recipe_ingredient_#{@line.id}", response.body
    assert_match "macros_chart", response.body
  end

  test "the unit can be cleared for things counted whole" do
    patch recipe_recipe_ingredient_url(@recipe, @line),
          params: { recipe_ingredient: { quantity: 1, unit: "" } },
          as: :turbo_stream

    assert_response :success
    assert_nil @line.reload.unit.presence
  end

  test "an ingredient can be added with no unit at all" do
    assert_difference("RecipeIngredient.count", 1) do
      post recipe_recipe_ingredients_url(@recipe),
           params: { recipe_ingredient: { ingredient_id: @breast.id, quantity: 1, unit: "" } },
           as: :turbo_stream
    end

    assert_response :success
    assert_nil @recipe.recipe_ingredients.order(:id).last.unit.presence
  end

  test "someone else's recipe can't have its ingredients edited" do
    sign_in users(:three)

    patch recipe_recipe_ingredient_url(@recipe, @line),
          params: { recipe_ingredient: { quantity: 99 } },
          as: :turbo_stream

    assert_response :not_found
    assert_equal 2.0, @line.reload.quantity
  end
end
