require "application_system_test_case"

# The Recipes page's "Recipe tags" tab loads tags/index into a frame; its
# New Tag and edit links open as full pages rather than inside the frame
# (which used to show "Content missing").
class RecipeTagsTabTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @tag = households(:one).tags.create!(tag: "Tab test tag", color: "#5f734c", user: users(:one))
    login_as users(:one), scope: :user
  end

  test "editing a tag from the Recipes page's tab opens the edit page" do
    visit recipes_url
    click_button "Recipe tags"

    within "#tags-index" do
      find("a[href='#{edit_tag_path(@tag)}']").click
    end

    assert_selector "h1", text: "Edit Tag"
    assert_no_text "Content missing"
    assert_current_path edit_tag_path(@tag)
  end

  test "New Tag from the tab opens the new tag page" do
    visit recipes_url
    click_button "Recipe tags"

    within("#tags-index") { click_link "New Tag" }

    assert_current_path new_tag_path
    assert_no_text "Content missing"
  end
end
