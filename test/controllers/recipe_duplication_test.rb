require "test_helper"

# "Copy this recipe" — forking one of the household's own recipes to build a
# variant from it.
class RecipeDuplicationTest < ActionDispatch::IntegrationTest
  setup do
    @alice  = users(:one)   # owner of household one
    @bob    = users(:two)   # member of household one
    @carol  = users(:three) # owner of household two

    @recipe = @alice.recipes.create!(title: "Chicken Teriyaki Bowls", description: "Weeknight",
                                     servings: 4, visibility: "public")
    @rice   = Ingredient.create!(ingredient: "Rice", family: "grain")
    @recipe.recipe_ingredients.create!(ingredient: @rice, quantity: 2.0, unit: "cup")
    @recipe.steps.create!(content: "Steam the rice")
    @recipe.tags << @alice.tags.create!(tag: "Dinner", color: "#5f734c")

    sign_in @alice
  end

  test "copying carries the whole recipe over under a distinct name" do
    assert_difference("Recipe.count", 1) do
      post duplicate_recipe_url(@recipe)
    end

    copy = Recipe.order(:id).last
    assert_redirected_to recipe_url(copy)

    assert_equal "Chicken Teriyaki Bowls (copy)", copy.title
    assert_equal "Weeknight", copy.description
    assert_equal 4, copy.servings
    assert_equal @alice, copy.user
    assert_equal @recipe, copy.source_recipe
    assert copy.private?, "a fresh variant starts private"

    assert_equal [@rice.id], copy.recipe_ingredients.map(&:ingredient_id)
    assert_equal [2.0], copy.recipe_ingredients.map(&:quantity)
    assert_equal ["cup"], copy.recipe_ingredients.map(&:unit)
    assert_equal ["Steam the rice"], copy.steps.map { |s| s.content.to_plain_text }
    assert_equal ["Dinner"], copy.tags.map(&:tag)
  end

  test "the original is left untouched" do
    post duplicate_recipe_url(@recipe)

    @recipe.reload
    assert_equal "Chicken Teriyaki Bowls", @recipe.title
    assert @recipe.public?
    assert_equal 1, @recipe.recipe_ingredients.count
  end

  test "repeat copies number themselves instead of stacking suffixes" do
    post duplicate_recipe_url(@recipe)
    post duplicate_recipe_url(@recipe)
    post duplicate_recipe_url(@recipe)

    assert_equal ["Chicken Teriyaki Bowls",
                  "Chicken Teriyaki Bowls (copy)",
                  "Chicken Teriyaki Bowls (copy 2)",
                  "Chicken Teriyaki Bowls (copy 3)"],
                 @alice.recipes.order(:id).pluck(:title)
  end

  test "copying a copy goes back to the original stem" do
    post duplicate_recipe_url(@recipe)
    copy = Recipe.order(:id).last

    post duplicate_recipe_url(copy)

    assert_equal "Chicken Teriyaki Bowls (copy 2)", Recipe.order(:id).last.title
  end

  test "editing the variant doesn't touch the recipe it came from" do
    post duplicate_recipe_url(@recipe)
    copy = Recipe.order(:id).last

    copy.update!(title: "Beef Teriyaki Bowls")
    copy.recipe_ingredients.first.update!(quantity: 3.0)

    @recipe.reload
    assert_equal "Chicken Teriyaki Bowls", @recipe.title
    assert_equal 2.0, @recipe.recipe_ingredients.first.quantity
  end

  test "a household member can fork a sibling's recipe they can't edit" do
    sign_in @bob

    assert_difference("Recipe.count", 1) do
      post duplicate_recipe_url(@recipe)
    end

    copy = Recipe.order(:id).last
    assert_equal @bob, copy.user
    assert_includes Recipe.for_household(@bob.household), copy
  end

  test "a recipe from outside the household can't be forked this way" do
    outside = @carol.recipes.create!(title: "Theirs", visibility: "public")

    assert_no_difference("Recipe.count") do
      post duplicate_recipe_url(outside)
    end
    assert_response :not_found
  end

  test "the copy button shows on our own recipes but not on public ones" do
    get recipes_url
    assert_select "form[action=?]", duplicate_recipe_path(@recipe)

    @carol.recipes.create!(title: "Theirs", visibility: "public")
    get recipes_url(scope: "public")
    assert_select "form[action*=?]", "/duplicate", count: 0
  end

  test "the recipe page offers the copy button" do
    get recipe_url(@recipe)

    assert_response :success
    assert_select "form[action=?]", duplicate_recipe_path(@recipe)
  end
end
