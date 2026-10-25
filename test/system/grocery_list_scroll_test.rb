require "application_system_test_case"

# Ticking things off the shopping list re-renders just that row; the page
# should stay where it was rather than jump back to the top.
class GroceryListScrollTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @user      = users(:one)
    @household = @user.household
    @week      = Date.current.beginning_of_week
    @household.grocery_lists.destroy_all
    @household.restock_items.destroy_all
    login_as @user, scope: :user
  end

  def scroll_y = page.evaluate_script("window.scrollY")

  test "checking off a grocery item keeps the scroll position" do
    items = 40.times.map do |n|
      ingredient = @household.ingredients.create!(ingredient: "Item #{n.to_s.rjust(2, '0')}", family: "produce", unit_price: 1)
      @household.grocery_lists.create!(user: @user, ingredient:, units: 1, week_of: @week)
    end
    last = items.last

    visit grocery_lists_url(date: @week)
    row = find("#grocery_list_#{last.id}")
    page.execute_script("arguments[0].scrollIntoView()", row)
    before = scroll_y
    assert before.positive?

    row.find("input[type=checkbox]").click
    assert_selector "#grocery_list_#{last.id} .line-through"

    assert_equal before, scroll_y
    assert last.reload.checked?
  end

  test "ticking off a restock item keeps the scroll position" do
    category = @household.restock_categories.ordered.first
    items = 40.times.map { |n| @household.restock_items.create!(user: @user, name: "Thing #{n}", restock_category: category, restock: true) }
    last = items.last

    visit grocery_lists_url(date: @week, list: "restock")
    row = find(".shopping_restock_item_#{last.id}")
    page.execute_script("arguments[0].scrollIntoView()", row)
    before = scroll_y
    assert before.positive?

    find("button[aria-label='Tick off #{last.name}']").click
    assert_selector "button[aria-label='Untick #{last.name}']"

    assert_equal before, scroll_y
    assert_equal Date.current, last.reload.last_restocked
  end
end
