require "test_helper"

class RecipeComponentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:one)
    @chicken = @user.recipes.create!(title: "Chicken", visibility: "private", servings: 4)
    @sauce   = @user.recipes.create!(title: "Lemon Garlic Sauce", visibility: "private", servings: 1)

    @cream = Ingredient.create!(ingredient: "Cream", family: "dairy")
    @sauce.recipe_ingredients.create!(ingredient: @cream, quantity: 2, unit: "cup")
    @sauce.steps.create!(content: "Reduce the cream")

    sign_in @user
  end

  test "adding a recipe as an ingredient" do
    assert_difference("RecipeComponent.count", 1) do
      post recipe_recipe_components_url(@chicken),
           params: { recipe_component: { component_recipe_id: @sauce.id, multiplier: 0.5 } }
    end

    assert_redirected_to recipe_url(@chicken)
    component = @chicken.recipe_components.sole
    assert_equal @sauce, component.component_recipe
    assert_equal 0.5, component.multiplier
  end

  test "the component's ingredients and steps show in their own sections" do
    @chicken.recipe_components.create!(component_recipe: @sauce, multiplier: 0.5)

    get recipe_url(@chicken)

    assert_response :success
    assert_select "#recipe_ingredients_section" do
      assert_select "a", text: "Lemon Garlic Sauce"
      # 2 cups at 0.5x
      assert_select "span[data-base-quantity='1.0']"
    end
    assert_select "#recipe_steps" do
      assert_select "a", text: "Lemon Garlic Sauce"
    end
    assert_match "Reduce the cream", response.body
    assert_match "0.5× batch", response.body
  end

  test "a circular reference is refused with an explanation" do
    @chicken.recipe_components.create!(component_recipe: @sauce)

    assert_no_difference("RecipeComponent.count") do
      post recipe_recipe_components_url(@sauce),
           params: { recipe_component: { component_recipe_id: @chicken.id } }
    end

    assert_redirected_to recipe_url(@sauce)
    assert_match(/circular/i, flash[:alert])
  end

  test "the picker leaves out the recipe itself and anything that would loop" do
    @chicken.recipe_components.create!(component_recipe: @sauce)

    get recipe_url(@sauce)

    assert_response :success
    assert_select "#new_component select option[value=?]", @chicken.id.to_s, count: 0
    assert_select "#new_component select option[value=?]", @sauce.id.to_s, count: 0
  end

  test "the multiplier can be adjusted in place" do
    component = @chicken.recipe_components.create!(component_recipe: @sauce)

    patch recipe_recipe_component_url(@chicken, component),
          params: { recipe_component: { multiplier: 2 } }, as: :turbo_stream

    assert_response :success
    assert_equal 2.0, component.reload.multiplier
    assert_match 'target="recipe_ingredients_section"', response.body
    assert_match 'target="recipe_steps"', response.body
    assert_match 'target="macros_chart"', response.body
  end

  test "removing a component leaves both recipes intact" do
    component = @chicken.recipe_components.create!(component_recipe: @sauce)

    assert_difference("RecipeComponent.count", -1) do
      delete recipe_recipe_component_url(@chicken, component)
    end

    assert_equal 2, Recipe.where(id: [@chicken.id, @sauce.id]).count
    assert_empty @chicken.reload.recipe_components
  end

  test "someone else's recipe can't have components attached" do
    theirs = users(:three).recipes.create!(title: "Theirs", visibility: "public")

    assert_no_difference("RecipeComponent.count") do
      post recipe_recipe_components_url(theirs),
           params: { recipe_component: { component_recipe_id: @sauce.id } }
    end
    assert_response :not_found
  end
end
