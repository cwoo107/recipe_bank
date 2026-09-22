require "test_helper"

# The globe/padlock beside the title is a toggle for the owner, the way the
# favourite star is.
class RecipeVisibilityToggleTest < ActionDispatch::IntegrationTest
  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Roast Chicken", visibility: "private")
    sign_in @user
  end

  test "the owner gets a button, and it says which way it will flip" do
    get recipe_url(@recipe)

    assert_response :success
    assert_select "#visibility_button_#{@recipe.id} form[action=?]",
                  toggle_visibility_recipe_path(@recipe)
    assert_select "button[aria-label=?]", "Make this recipe public"

    @recipe.update!(visibility: "public")
    get recipe_url(@recipe)
    assert_select "button[aria-label=?]", "Make this recipe private"
  end

  test "someone else viewing a public recipe gets a plain icon, not a button" do
    @recipe.update!(visibility: "public")
    sign_in users(:three)

    get recipe_url(@recipe)

    assert_response :success
    assert_select "#visibility_button_#{@recipe.id}"
    assert_select "form[action=?]", toggle_visibility_recipe_path(@recipe), count: 0
  end

  test "clicking it flips private to public and back" do
    patch toggle_visibility_recipe_url(@recipe), as: :turbo_stream
    assert_response :success
    assert @recipe.reload.public?

    patch toggle_visibility_recipe_url(@recipe), as: :turbo_stream
    assert_response :success
    assert @recipe.reload.private?
  end

  test "the toggle swaps itself out in place" do
    patch toggle_visibility_recipe_url(@recipe), as: :turbo_stream

    assert_match "target=\"visibility_button_#{@recipe.id}\"", response.body
    assert_match "Make this recipe private", response.body
  end

  test "going private pulls the recipe out of other households' browse list" do
    @recipe.update!(visibility: "public")
    other = households(:two)
    assert_includes Recipe.public_beyond_household(other), @recipe

    patch toggle_visibility_recipe_url(@recipe), as: :turbo_stream

    refute_includes Recipe.public_beyond_household(other), @recipe.reload
  end

  test "someone else can't flip your recipe" do
    @recipe.update!(visibility: "public")
    sign_in users(:three)

    patch toggle_visibility_recipe_url(@recipe), as: :turbo_stream

    assert @recipe.reload.public?
    assert_redirected_to recipes_url
  end

  test "a bogus size can't be smuggled into the icon's class list" do
    patch toggle_visibility_recipe_url(@recipe),
          params: { size: "size-5 fixed inset-0 z-50" }, as: :turbo_stream

    assert_response :success
    assert_no_match "inset-0", response.body
    assert_match "size-5", response.body
  end

  test "the size the button was rendered at survives the round trip" do
    patch toggle_visibility_recipe_url(@recipe), params: { size: "size-7" }, as: :turbo_stream

    assert_match "size-7", response.body
  end
end
