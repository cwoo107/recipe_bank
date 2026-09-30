require "application_system_test_case"

# Building a recipe out of another recipe, from the page.
class RecipeComponentsTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @user    = users(:one)
    @chicken = @user.recipes.create!(title: "Chicken Thighs", visibility: "private", servings: 4)
    @sauce   = @user.recipes.create!(title: "Lemon Garlic Sauce", visibility: "private", servings: 1)

    cream = Ingredient.create!(household: households(:one), ingredient: "Cream", family: "dairy")
    @sauce.recipe_ingredients.create!(ingredient: cream, quantity: 2, unit: "cup")
    @sauce.steps.create!(content: "Reduce the cream by half")

    login_as @user, scope: :user
  end

  test "adding a recipe as an ingredient gives it its own sections" do
    visit recipe_url(@chicken)
    click_button "Edit"

    within "#new_component" do
      # The searchable picker (searchable_select_controller.js) hides the
      # real <select> behind a type-to-search input.
      find("input[placeholder='Search for a recipe...']").fill_in(with: "Lemon")
      find("[data-searchable-select-target=option]", text: "Lemon Garlic Sauce").click
      fill_in "Batches", with: "0.5"
      click_button "Add recipe"
    end

    assert_text "Added Lemon Garlic Sauce"

    within "#recipe_ingredients_section" do
      assert_link "Lemon Garlic Sauce"
      assert_text "Cream"
      assert_text "0.5× batch"
      # 2 cups at 0.5x. Asserted on the scaler's base so "1" can't match
      # some other number on the page.
      assert_selector "span[data-base-quantity='1.0']"
    end

    within "#recipe_steps" do
      assert_link "Lemon Garlic Sauce"
      assert_text "Reduce the cream by half"
    end

    assert_equal [@sauce], @chicken.reload.component_recipes
  end

  test "public recipes only show in the picker once the toggle is on" do
    pesto = users(:three).recipes.create!(title: "Public Pesto", visibility: "public", servings: 2)

    visit recipe_url(@chicken)
    click_button "Edit"

    within "#new_component" do
      # Just opening the list, before typing anything, must already leave
      # public recipes out while the toggle is off.
      find("input[placeholder='Search for a recipe...']").click
      assert_selector "[data-searchable-select-target=option]", text: "Lemon Garlic Sauce"
      assert_no_selector "[data-searchable-select-target=option]", text: "Public Pesto"

      find("input[placeholder='Search for a recipe...']").fill_in(with: "Pesto")
      assert_no_selector "[data-searchable-select-target=option]", text: "Public Pesto"

      check "Also browse public recipes"
      find("input[placeholder='Search for a recipe...']").fill_in(with: "Pesto")
      find("[data-searchable-select-target=option]", text: "Public Pesto").click
      click_button "Add recipe"
    end

    assert_text "Added Public Pesto"
    assert_equal [ pesto ], @chicken.reload.component_recipes
  end

  test "editing the component recipe flows through to the one using it" do
    @chicken.recipe_components.create!(component_recipe: @sauce)

    visit recipe_url(@sauce)
    click_button "Edit"
    # Capybara doesn't match aria-label by default, and these controls are
    # labelled that way rather than with visible text.
    find("input[aria-label='Quantity of Cream']").set("3")
    find("body").click
    assert_selector "input[aria-label='Quantity of Cream'][value='3.0']"

    visit recipe_url(@chicken)
    within "#recipe_ingredients_section" do
      assert_text "Cream"
      assert_selector "span[data-base-quantity='3.0']", wait: 5
    end
  end

  test "a component can be removed again from the recipe using it" do
    @chicken.recipe_components.create!(component_recipe: @sauce)
    visit recipe_url(@chicken)

    assert_text "Lemon Garlic Sauce"
    click_button "Edit"
    find("button[aria-label='Remove Lemon Garlic Sauce from this recipe']").click
    within "dialog[data-controller='turbo-confirm']" do
      assert_text "Remove Lemon Garlic Sauce from this recipe?"
      click_button "Confirm"
    end

    assert_text "Removed Lemon Garlic Sauce"
    assert_empty @chicken.reload.recipe_components
    assert Recipe.exists?(@sauce.id), "the sauce recipe itself survives"
  end
end
