require "test_helper"

# Covers the household-first recipe list and the "save a public recipe" flow.
class RecipesBrowsingTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)   # owner of household one
    @bob   = users(:two)   # member of household one
    @carol = users(:three) # owner of household two

    @ours    = @bob.recipes.create!(title: "Household Stew",  visibility: "private")
    @theirs  = @carol.recipes.create!(title: "Public Paella", visibility: "public")
    @hidden  = @carol.recipes.create!(title: "Secret Sauce",  visibility: "private")

    sign_in @alice
  end

  test "index defaults to the household's recipes" do
    get recipes_url

    assert_response :success
    assert_match "Household Stew", response.body
    assert_no_match "Public Paella", response.body
  end

  test "index in public scope shows only outside public recipes" do
    get recipes_url(scope: "public")

    assert_response :success
    assert_match "Public Paella", response.body
    assert_no_match "Household Stew", response.body
    assert_no_match "Secret Sauce", response.body
  end

  test "an unknown scope falls back to the household list" do
    get recipes_url(scope: "everything")

    assert_response :success
    assert_match "Household Stew", response.body
    assert_no_match "Public Paella", response.body
  end

  test "search stays inside the chosen scope" do
    get recipes_url(query: "Paella")
    assert_no_match "Public Paella", response.body

    get recipes_url(scope: "public", query: "Paella")
    assert_match "Public Paella", response.body

    get recipes_url(scope: "public", query: "Stew")
    assert_no_match "Household Stew", response.body
  end

  test "a household member can open a sibling's private recipe" do
    get recipe_url(@ours)
    assert_response :success
  end

  test "another household's private recipe is not reachable" do
    get recipe_url(@hidden)
    assert_response :not_found
  end

  test "saving a public recipe copies it into the household" do
    assert_difference("Recipe.count", 1) do
      post save_to_household_recipe_url(@theirs)
    end

    copy = Recipe.for_household(@alice.household).find_by(source_recipe: @theirs)
    assert_equal @alice, copy.user
    assert_redirected_to recipe_url(copy)
  end

  test "a public recipe offers the save button, then a link to the copy" do
    get recipe_url(@theirs)
    assert_match "Save to Our Recipes", response.body

    post save_to_household_recipe_url(@theirs)

    get recipe_url(@theirs)
    assert_match "Open your copy", response.body
    assert_no_match "Save to Our Recipes", response.body
  end

  test "the browse list marks recipes the household already saved" do
    get recipes_url(scope: "public")
    assert_match save_to_household_recipe_path(@theirs), response.body
    assert_no_match "Already in your recipes", response.body

    post save_to_household_recipe_url(@theirs)

    get recipes_url(scope: "public")
    assert_no_match save_to_household_recipe_path(@theirs), response.body
    assert_match "Already in your recipes", response.body
  end

  test "saving the same recipe twice sends you to the copy you already have" do
    post save_to_household_recipe_url(@theirs)
    copy = Recipe.find_by(source_recipe: @theirs)

    assert_no_difference("Recipe.count") do
      post save_to_household_recipe_url(@theirs)
    end
    assert_redirected_to recipe_url(copy)
  end

  test "a recipe the household already owns cannot be saved again" do
    ours_public = @bob.recipes.create!(title: "Ours Publicly", visibility: "public")

    assert_no_difference("Recipe.count") do
      post save_to_household_recipe_url(ours_public)
    end
    assert_redirected_to recipes_url(scope: "public")
  end

  test "a private recipe cannot be saved" do
    assert_no_difference("Recipe.count") do
      post save_to_household_recipe_url(@hidden)
    end
    assert_response :not_found
  end
end
