require "test_helper"

# The Recipes and Ingredients searches match tags as well as names.
class SearchByTagTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
    @household = households(:one)
    @weeknight = tags(:one) # "Weeknight"
    @weekend   = @household.tags.create!(tag: "Weekend", color: "#7a8f62", user: users(:one))

    @pasta = users(:one).recipes.create!(title: "Lemon Pasta", servings: 4)
    @pasta.tags << @weeknight << @weekend
    @stew = users(:one).recipes.create!(title: "Beef Stew", servings: 4)

    @rice = @household.ingredients.create!(ingredient: "Basmati Rice", family: "grain")
    @rice.tags << @weeknight << @weekend
    @household.ingredients.create!(ingredient: "Zzqqx Flour", family: "grain")
  end

  # The page draws each recipe twice (phone cards and the desktop table), so
  # compare against a search that finds it by title.
  def links_to(recipe) = css_select("a[href='#{recipe_path(recipe)}']").size

  test "a recipe is found by one of its tags" do
    get recipes_url(query: "weeknight")

    assert_select "a[href=?]", recipe_path(@pasta)
    assert_select "a[href=?]", recipe_path(@stew), count: 0
  end

  test "a recipe with several matching tags is listed once" do
    get recipes_url(query: "Lemon")
    by_title = links_to(@pasta)

    get recipes_url(query: "week") # Weeknight and Weekend both match
    assert_equal by_title, links_to(@pasta)
  end

  test "names still match, alongside the tag filter" do
    get recipes_url(query: "lemon", filter: @weeknight.id)

    assert_select "a[href=?]", recipe_path(@pasta)
  end

  test "an ingredient is found by one of its tags, and listed once" do
    get ingredients_url(query: "basmati")
    by_name = css_select("a[href='#{ingredient_path(@rice)}']").size

    get ingredients_url(query: "week") # Weeknight and Weekend both match

    assert_response :success
    assert_operator by_name, :>, 0
    assert_equal by_name, css_select("a[href='#{ingredient_path(@rice)}']").size
    assert_no_match(/Zzqqx flour/i, response.body)
  end
end
