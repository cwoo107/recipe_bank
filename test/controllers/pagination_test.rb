require "test_helper"

# The recipes and ingredients lists page through long lists (Pagy, see
# shared/_pagination), keeping the page's search, filter and sort.
class PaginationTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  def recipe_rows = css_select("tbody tr").size

  test "recipes come a page at a time, with links to the rest" do
    30.times { |n| users(:one).recipes.create!(title: "Paged recipe #{n.to_s.rjust(2, '0')}", servings: 2) }
    total = Recipe.for_household(households(:one)).count

    get recipes_url
    assert_equal RecipesController::RECIPES_PER_PAGE, recipe_rows
    assert_select "nav.pagy.series-nav[aria-label='Recipes pages']"
    assert_select ".pagy.info", text: "Showing 1–#{RecipesController::RECIPES_PER_PAGE} of #{total} recipes"
    assert_select "nav.pagy a[aria-current]", text: "1"
    assert_select "nav.pagy a[rel=next][aria-label=Next] svg"           # chevron icon, not "&gt;"
    assert_select "nav.pagy a[aria-disabled][aria-label=Previous] svg"  # nothing before page 1

    get recipes_url(page: 2)
    assert_equal total - RecipesController::RECIPES_PER_PAGE, recipe_rows
    assert_select "nav.pagy a[aria-current]", text: "2"
  end

  test "page links keep the search and sort" do
    30.times { |n| users(:one).recipes.create!(title: "Soup #{n}", servings: 2) }

    get recipes_url(query: "soup", sort: "title", direction: "desc")

    assert_select "nav.pagy a[href*='page=2'][href*='query=soup'][href*='sort=title'][href*='direction=desc']"
  end

  test "sorting by a counted column still pages" do
    30.times { |n| users(:one).recipes.create!(title: "Counted #{n}", servings: 2) }

    get recipes_url(sort: "ingredients")

    assert_response :success
    assert_equal RecipesController::RECIPES_PER_PAGE, recipe_rows
  end

  test "a short list has no page links" do
    get recipes_url

    assert_select "nav.pagy", 0
  end

  test "ingredients come a page at a time too, keeping the filter" do
    60.times { |n| households(:one).ingredients.create!(ingredient: "Paged produce #{n}", family: "produce") }

    get ingredients_url(filter: "produce")
    assert_select "tbody tr", IngredientsController::INGREDIENTS_PER_PAGE
    assert_select "nav.pagy a[href*='page=2'][href*='filter=produce']"

    get ingredients_url(filter: "produce", page: 2)
    assert_select "nav.pagy a[aria-current]", text: "2"
  end

  test "an ingredient's Used in Recipes list pages too, by recipe title" do
    rice = households(:one).ingredients.create!(ingredient: "Paged rice", family: "grain")
    15.times do |n|
      recipe = users(:one).recipes.create!(title: "Rice dish #{n.to_s.rjust(2, '0')}", servings: 2)
      recipe.recipe_ingredients.create!(ingredient: rice, quantity: 1, unit: "cup")
    end

    get ingredient_url(rice)
    assert_select "ul li", IngredientsController::RECIPES_PER_PAGE
    assert_select "ul li:first-child", text: /Rice dish 00/
    assert_select ".pagy.info", text: "Showing 1–10 of 15 recipes"

    get ingredient_url(rice, page: 2)
    assert_select "ul li", 5
    assert_select "ul li:first-child", text: /Rice dish 10/
  end
end
