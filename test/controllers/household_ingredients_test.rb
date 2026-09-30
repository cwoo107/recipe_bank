require "test_helper"

# Each household works from its own ingredient library.
class HouseholdIngredientsTest < ActionDispatch::IntegrationTest
  setup do
    @alice  = users(:one)   # owner of household one
    @ours   = households(:one).ingredients.create!(ingredient: "Our paprika")
    @theirs = households(:two).ingredients.create!(ingredient: "Their paprika")
    @recipe = @alice.recipes.create!(title: "Goulash")
    sign_in @alice
  end

  test "the ingredients page lists only the household's own" do
    get ingredients_url

    assert_match "Our paprika", response.body
    assert_no_match "Their paprika", response.body
  end

  test "the recipe page's picker offers only the household's own" do
    get recipe_url(@recipe)

    assert_select "select[name='recipe_ingredient[ingredient_id]'] option", text: "Our paprika"
    assert_select "select[name='recipe_ingredient[ingredient_id]'] option", text: "Their paprika", count: 0
  end

  test "a new ingredient joins the creator's household" do
    post ingredients_url, params: { ingredient: { ingredient: "Caraway" } }

    assert_equal households(:one), Ingredient.find_by!(ingredient: "Caraway").household
  end

  test "another household's ingredient can't be added to a recipe by id" do
    assert_no_difference("RecipeIngredient.count") do
      post recipe_recipe_ingredients_url(@recipe),
           params: { recipe_ingredient: { ingredient_id: @theirs.id, quantity: 1, unit: "tsp" } },
           as: :turbo_stream
    end
  end

  test "another household's ingredient can't be edited or deleted" do
    patch ingredient_url(@theirs), params: { ingredient: { ingredient: "Mine now" } }
    assert_equal "Their paprika", @theirs.reload.ingredient

    assert_no_difference("Ingredient.count") { delete ingredient_url(@theirs) }
  end
end
