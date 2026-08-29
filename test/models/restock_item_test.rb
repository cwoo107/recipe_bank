require "test_helper"

class RestockItemTest < ActiveSupport::TestCase
  test "position is scoped to the list, shared across household members" do
    household = households(:one)
    category  = restock_categories(:kitchen_one)
    alice = users(:one)
    bob = users(:two) # also in household :one

    first = household.restock_items.create!(user: alice, name: "First", restock_category: category)
    second = household.restock_items.create!(user: bob, name: "Second", restock_category: category)

    assert_equal 1, first.reload.position
    assert_equal 2, second.reload.position
  end

  test "move_to_list! moves the item into the new list at the given position" do
    household = households(:one)
    item = household.restock_items.create!(user: users(:one), name: "Paper towels", restock_category: restock_categories(:kitchen_one))

    item.move_to_list!(restock_categories(:bathrooms_one).id, 1)

    assert_equal restock_categories(:bathrooms_one), item.restock_category
    assert_equal 1, item.position
  end

  test "requires a name" do
    item = RestockItem.new(household: households(:one), user: users(:one), restock_category: restock_categories(:kitchen_one))
    assert_not item.valid?
    assert_includes item.errors[:name], "can't be blank"
  end

  test "mark_stocked! sets stocked, clears restock, and stamps the check date" do
    item = restock_items(:one)
    item.update!(restock: true)

    item.mark_stocked!

    assert item.stocked?
    assert_not item.restock?
    assert_equal Date.current, item.last_date_checked_stocked.to_date
    assert item.stocked_badge?
    assert_not item.restock_badge?
  end

  test "mark_restock! sets restock, clears stocked, and stamps the check date" do
    item = restock_items(:one)
    item.update!(stocked: true)

    item.mark_restock!

    assert item.restock?
    assert_not item.stocked?
    assert_equal Date.current, item.last_date_checked_restocked.to_date
    assert item.restock_badge?
    assert_not item.stocked_badge?
  end

  test "a badge only shows while the check happened this week" do
    item = restock_items(:one)
    item.update!(stocked: true, last_date_checked_stocked: 2.weeks.ago)

    assert_not item.stocked_badge?
  end

  test "checked_this_week? is false until a check-in happens, then true" do
    item = restock_items(:one)
    assert_not item.checked_this_week?

    item.mark_stocked!
    assert item.checked_this_week?
  end

  test "checked_this_week? goes back to false once the check-in is stale" do
    item = restock_items(:one)
    item.update!(stocked: true, last_date_checked_stocked: 2.weeks.ago)

    assert_not item.checked_this_week?
  end
end
