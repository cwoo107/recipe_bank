require "test_helper"

# The Recipes and Ingredients searches match whatever the capitalization.
# (SQLite's LIKE ignores case anyway, so this mostly guards the query shape;
# production's Postgres LIKE doesn't — hence LOWER on both sides.)
class CaseInsensitiveSearchTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
    @recipe = users(:one).recipes.create!(title: "Chicken Teriyaki Bowls", servings: 4)
    households(:one).ingredients.create!(ingredient: "Basmati Rice", family: "grain")
  end

  test "recipe search ignores capitalization" do
    get recipes_url(query: "cHICKEN teriyaki")

    assert_response :success
    assert_select "a[href=?]", recipe_path(@recipe)
  end

  test "ingredient search ignores capitalization" do
    get ingredients_url(query: "BASMATI")

    assert_response :success
    assert_match(/Basmati rice/i, response.body)
  end

  test "a % or _ in the search is matched literally, not as a wildcard" do
    get recipes_url(query: "%")

    assert_response :success
    assert_select "a[href=?]", recipe_path(@recipe), count: 0
  end
end
