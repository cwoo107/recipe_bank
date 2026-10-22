require "application_system_test_case"

# Typing a name that isn't in the household's ingredients into the recipe
# page's picker adds it to the library and the recipe in one go — no
# separate form.
class RecipeNewIngredientTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Cookies", visibility: "private", servings: 24)
    households(:one).ingredients.create!(ingredient: "Butter")
    login_as @user, scope: :user
    visit recipe_url(@recipe)
    click_button "Edit"
  end

  test "a new name is offered in the dropdown and added with the line" do
    assert_no_link "create a new ingredient"

    picker = find("input[placeholder='Search or type a new ingredient...']")
    picker.fill_in with: "chocolate chips"
    # The wrapper and dropdown around the offer share its text, so match the offer itself.
    find("[data-action='click->searchable-select#chooseNew']", text: "Add “chocolate chips” as a new ingredient", exact_text: true).click

    fill_in "Quantity", with: "2"
    select "cup", from: "Unit (optional)"
    click_button "Add Ingredient"

    assert_text "Chocolate chips"
    line = @recipe.recipe_ingredients.last
    assert_equal [ "Chocolate chips", 2.0, "cup" ], [ line.ingredient.ingredient, line.quantity, line.unit ]
  end

  test "typing an existing name picks it rather than offering a new one" do
    picker = find("input[placeholder='Search or type a new ingredient...']")
    picker.fill_in with: "butter"
    assert_no_text "Add “butter” as a new ingredient"

    fill_in "Quantity", with: "1"
    assert_no_difference("Ingredient.count") do
      click_button "Add Ingredient"
      assert_selector "[id^=recipe_ingredient_]", text: "Butter"
    end
  end

  # Turbo's cache and moved elements connect the picker again; it should
  # rebuild its one search box, not add a second.
  test "connecting the picker again keeps a single search box" do
    boxes = "return document.querySelector(\"[data-controller~='searchable-select']\")" \
            ".querySelectorAll(\"[data-searchable-select-target='wrapper']\").length"
    assert_equal 1, page.evaluate_script("(() => { #{boxes} })()")

    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller~='searchable-select']")
      const parent = el.parentNode, next = el.nextSibling
      el.remove()
      parent.insertBefore(el, next)
    JS

    assert_equal 1, page.evaluate_script("(() => { #{boxes} })()")
  end
end
