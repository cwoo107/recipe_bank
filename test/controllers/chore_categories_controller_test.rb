require "test_helper"

class ChoreCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, household :one
  end

  test "create adds a category to the household" do
    assert_difference("households(:one).chore_categories.count") do
      post chore_categories_url, params: { chore_category: { name: "Yard" } }
    end
    assert_redirected_to chores_url
  end

  test "update renames a category" do
    patch chore_category_url(chore_categories(:chores_one)), params: { chore_category: { name: "Odd jobs" } }
    assert_equal "Odd jobs", chore_categories(:chores_one).reload.name
  end

  test "destroy leaves the category's chores uncategorized" do
    delete chore_category_url(chore_categories(:chores_one))
    assert_nil chores(:one).reload.chore_category_id
  end

  test "cannot touch another household's category" do
    delete chore_category_url(chore_categories(:chores_two))
    assert_response :not_found
  end

  test "new households get the default categories" do
    household = Household.create!(family_name: "New", owner: users(:two))
    assert_equal ChoreCategory::DEFAULT_NAMES, household.chore_categories.ordered.pluck(:name)
  end

  test "new and edit render the dialog forms" do
    get new_chore_category_url(return_to: "/weekly_chores", frame: "new_chore_category_ab12")
    assert_select "turbo-frame#new_chore_category_ab12 form"

    get edit_chore_category_url(chore_categories(:chores_one), return_to: "/weekly_chores")
    assert_select "turbo-frame#edit_chore_category_#{chore_categories(:chores_one).id} form"
    assert_select "form[action=?] button", chore_category_path(chore_categories(:chores_one), return_to: "/weekly_chores"), text: "Delete category"
  end

  test "create from the board returns to the board" do
    post chore_categories_url, params: { chore_category: { name: "Yard" }, return_to: "/weekly_chores?date=2026-09-28" }
    assert_redirected_to "/weekly_chores?date=2026-09-28"
  end

  test "create ignores an external return_to" do
    post chore_categories_url, params: { chore_category: { name: "Yard" }, return_to: "https://evil.example.com" }
    assert_redirected_to chores_url
  end

  test "the board shows the add-category tile and clickable category names to admins" do
    get weekly_chores_url
    assert_select "button", text: "Add a chore category"
    assert_select "button[title=?]", "Rename or delete Standard Cleaning", text: "Standard Cleaning"
  end

  test "reorder saves the new row order" do
    standard = chore_categories(:standard_cleaning_one)
    chores_cat = chore_categories(:chores_one)

    post reorder_chore_categories_url, params: { order: [ chores_cat.id, standard.id ] }

    assert_response :ok
    assert_equal [ chores_cat, standard ], households(:one).chore_categories.ordered.to_a
  end

  test "reorder ignores another household's categories" do
    other = chore_categories(:chores_two)

    post reorder_chore_categories_url, params: { order: [ other.id ] }

    assert_equal 1, other.reload.position
  end
end
