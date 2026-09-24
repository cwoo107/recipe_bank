require "application_system_test_case"

class TodoQuickAddTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  test "several tasks can be entered in a row without reopening" do
    login_as users(:one), scope: :user
    visit todos_url

    click_button "Add a task"
    within "dialog[open]" do
      fill_in "Title", with: "First"
      click_button "Create task"
    end
    assert_selector "#todos_todo", text: "First"

    within "dialog[open]" do
      fill_in "Title", with: "Second"
      click_button "Create task"
    end
    assert_selector "#todos_todo", text: "Second"

    assert_selector "dialog[open]"
    assert_equal ["Second", "First"], Todo.order(id: :desc).limit(2).pluck(:title)
  end

  test "the per-column quick add stays open too" do
    login_as users(:one), scope: :user
    visit todos_url

    find("button[aria-label='Add task to In Progress']").click
    assert_selector "dialog[open]"

    within "dialog[open]" do
      fill_in "Title", with: "Column task"
      click_button "Create task"
    end

    assert_selector "#todos_in_progress", text: "Column task"
    assert_selector "dialog[open]"
    within("dialog[open]") { assert_field "Title", with: "" }
  end

  test "the quick-add dialog stays open and blank for the next task" do
    login_as users(:one), scope: :user
    visit todos_url

    click_button "Add a task"
    assert_selector "dialog[open]"

    within "dialog[open]" do
      fill_in "Title", with: "Buy milk"
      click_button "Create task"
    end

    assert_selector "#todos_todo", text: "Buy milk"
    assert_selector "dialog[open]", wait: 5
    within("dialog[open]") { assert_field "Title", with: "" }
  end
end
