require "test_helper"

class RecipeTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, an admin of household :one
    @recipe = Recipe.create!(title: "Tacos", servings: 4, user: users(:one))
  end

  test "tags a household recipe with one of the household's tags" do
    assert_difference("@recipe.tags.count") do
      post recipe_recipe_tags_url(@recipe), params: { recipe_tag: { tag_id: tags(:one).id } }
    end
    assert_redirected_to recipe_url(@recipe)
  end

  test "won't use another household's tag" do
    assert_no_difference("RecipeTag.count") do
      post recipe_recipe_tags_url(@recipe), params: { recipe_tag: { tag_id: tags(:two).id } }
    end
  end

  test "won't tag another household's recipe" do
    theirs = Recipe.create!(title: "Their stew", servings: 4, user: users(:three), visibility: "public")

    assert_no_difference("RecipeTag.count") do
      post recipe_recipe_tags_url(theirs), params: { recipe_tag: { tag_id: tags(:one).id } }
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

    assert_select "select[name='recipe_tag[tag_id]']" do
      assert_select "option", text: "Spicy"
      assert_select "option", text: "Weeknight", count: 0 # already on it
      assert_select "option", text: "Holiday", count: 0   # household :two's
    end
  end

  test "the recipes page filters by the household's tags only" do
    get recipes_url

    assert_select "a[href*='filter=#{tags(:one).id}']"
    assert_select "a[href*='filter=#{tags(:two).id}']", 0
  end
end
