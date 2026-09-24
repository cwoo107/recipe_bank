require "application_system_test_case"

# What the header offers in each mode. Both toggle labels live in the DOM at
# once, so these assert on the button's *visible* text rather than using
# assert_button, whose XPath match ignores CSS visibility.
class RecipeEditModeTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @user   = users(:one)
    @recipe = @user.recipes.create!(title: "Roast Chicken", description: "Sunday",
                                    visibility: "private", servings: 4)
  end

  def edit_toggle = find("button[data-edit-mode-target='editButton']")

  test "entering edit mode swaps Edit for Save edits and puts Copy away" do
    login_as @user, scope: :user
    visit recipe_url(@recipe)

    assert_equal "Edit", edit_toggle.text
    assert_button "Copy"

    click_button "Edit"

    assert_equal "Save edits", edit_toggle.text
    assert_no_button "Copy"
    # The rest of edit mode still arrives with it.
    assert_button "Delete"
    assert_field "recipe[title]", with: "Roast Chicken"
  end

  test "leaving edit mode puts the header back" do
    login_as @user, scope: :user
    visit recipe_url(@recipe)

    click_button "Edit"
    assert_equal "Save edits", edit_toggle.text

    edit_toggle.click

    assert_equal "Edit", edit_toggle.text
    assert_button "Copy"
    assert_no_button "Delete"
  end
end
