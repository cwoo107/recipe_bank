require "test_helper"

class RecipeTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, an admin of household :one
    @recipe = Recipe.create!(title: "Tacos", servings: 4, user: users(:one))
  end

  test "tags a household recipe with one of the household's tags" do
    assert_difference("@recipe.tags.count") do
      post recipe_recipe_tags_url(@recipe), params: { recipe_tag: { tag_names: "weeknight" } }
    end
    assert_redirected_to recipe_url(@recipe)
    assert_equal [ tags(:one) ], @recipe.tags.to_a
  end

  test "adds several tags at once, creating the ones the household doesn't have" do
    assert_difference("@recipe.tags.count", 2) do
      post recipe_recipe_tags_url(@recipe), params: { recipe_tag: { tag_names: "Weeknight, Spicy, " } }
    end
    spicy = households(:one).tags.find_by(tag: "Spicy")
    assert spicy.color.present?
    assert_includes @recipe.tags, spicy
  end

  test "won't use another household's tag" do
    post recipe_recipe_tags_url(@recipe), params: { recipe_tag: { tag_names: "Holiday" } }

    assert_not_includes @recipe.tags, tags(:two)
    assert_equal households(:one), @recipe.tags.find_by(tag: "Holiday").household
  end

  test "won't tag another household's recipe" do
    theirs = Recipe.create!(title: "Their stew", servings: 4, user: users(:three), visibility: "public")

    assert_no_difference("RecipeTag.count") do
      post recipe_recipe_tags_url(theirs), params: { recipe_tag: { tag_names: "Weeknight" } }
    end
    assert_response :not_found
  end

  test "removes a tag" do
    link = @recipe.recipe_tags.create!(tag: tags(:one))

    assert_difference("RecipeTag.count", -1) { delete recipe_recipe_tag_url(@recipe, link) }
  end

  test "the recipe page only offers the household's tags it doesn't already have" do
    @recipe.recipe_tags.create!(tag: tags(:one))
    households(:one).tags.create!(tag: "Spicy", color: "#b5806a")

    get recipe_url(@recipe)

    picker = css_select("[data-controller=tag-picker]").find { |el| el.at_css("input[name='recipe_tag[tag_names]']") }
    offered = JSON.parse(picker["data-tag-picker-options-value"]).map { |option| option["name"] }
    assert_includes offered, "Spicy"
    assert_not_includes offered, "Weeknight" # already on it
    assert_not_includes offered, "Holiday"   # household :two's
  end

  test "the recipes page filters by the household's tags only" do
    get recipes_url

    assert_select "a[href*='filter=#{tags(:one).id}']"
    assert_select "a[href*='filter=#{tags(:two).id}']", 0
  end
end
