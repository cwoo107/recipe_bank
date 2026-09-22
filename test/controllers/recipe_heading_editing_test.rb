require "test_helper"

# Inline title/description editing from the recipe page's edit mode.
class RecipeHeadingEditingTest < ActionDispatch::IntegrationTest
  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Roast Chicken", description: "Sunday dinner",
                                    visibility: "private", servings: 4)
    sign_in @user
  end

  test "the owner gets title and description fields alongside the read-only text" do
    get recipe_url(@recipe)

    assert_response :success
    assert_select "h1#recipe_title[data-edit-mode-target=viewOnlyItems]", text: /Roast Chicken/
    assert_select "#recipe_description p[data-edit-mode-target=viewOnlyItems]", text: /Sunday dinner/
    assert_select "[data-edit-mode-target=editOnlyItems] input[name=?][value=?]",
                  "recipe[title]", "Roast Chicken"
    assert_select "[data-edit-mode-target=editOnlyItems] textarea[name=?]", "recipe[description]",
                  text: /Sunday dinner/
  end

  test "a description field is offered even when there isn't one yet" do
    @recipe.update!(description: nil)

    get recipe_url(@recipe)

    assert_select "#recipe_description"   # empty, but present as a replace target
    assert_select "textarea[name=?]", "recipe[description]"
  end

  test "someone else viewing a public recipe gets no editable fields" do
    @recipe.update!(visibility: "public")
    sign_in users(:three)

    get recipe_url(@recipe)

    assert_response :success
    assert_select "h1#recipe_title", text: /Roast Chicken/
    assert_select "input[name=?]", "recipe[title]", count: 0
  end

  test "saving swaps the read-only text and leaves the form alone" do
    patch recipe_url(@recipe, format: :turbo_stream),
          params: { recipe: { title: "Roast Duck", description: "Even better" } }

    assert_response :success
    @recipe.reload
    assert_equal "Roast Duck", @recipe.title
    assert_equal "Even better", @recipe.description

    assert_match 'target="recipe_title"', response.body
    assert_match 'target="recipe_description"', response.body
    assert_match "Roast Duck", response.body
    # The form isn't in the response, so what the user is typing survives.
    assert_no_match 'name="recipe[title]"', response.body
  end

  test "editing the heading leaves the recipe's other attributes alone" do
    patch recipe_url(@recipe, format: :turbo_stream), params: { recipe: { title: "Roast Duck" } }

    @recipe.reload
    assert_equal 4, @recipe.servings
    assert_equal "private", @recipe.visibility
  end

  test "the description can be cleared" do
    patch recipe_url(@recipe, format: :turbo_stream), params: { recipe: { description: "" } }

    assert_response :success
    assert_nil @recipe.reload.description.presence
  end

  test "a rejected title comes back with the error and the field intact" do
    patch recipe_url(@recipe, format: :turbo_stream), params: { recipe: { title: "" } }

    assert_response :unprocessable_entity
    assert_equal "Roast Chicken", @recipe.reload.title
    assert_match 'target="recipe_heading"', response.body
    assert_match "Title can&#39;t be blank", response.body
  end

  test "the full edit page still redirects rather than streaming" do
    patch recipe_url(@recipe), params: { recipe: { title: "Roast Goose" } }

    assert_redirected_to recipe_url(@recipe)
    assert_equal "Roast Goose", @recipe.reload.title
  end

  test "someone else's recipe can't be renamed" do
    @recipe.update!(visibility: "public")
    sign_in users(:three)

    patch recipe_url(@recipe, format: :turbo_stream), params: { recipe: { title: "Hijacked" } }

    assert_equal "Roast Chicken", @recipe.reload.title
  end
end
