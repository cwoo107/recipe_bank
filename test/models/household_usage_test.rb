require "test_helper"

class HouseholdUsageTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
  end

  def usage(feature) = Household::Usage.new(@household).rows.find { |row| row.feature == feature }

  test "counts things people did, in all and in the last 30 days, with when last used" do
    recipe = Recipe.create!(title: "Old soup", user: users(:two))
    recipe.update_columns(created_at: 40.days.ago)
    Recipe.create!(title: "New soup", user: users(:one))

    row = usage("Recipes")
    assert_operator row.total, :>=, 2
    assert_operator row.recent, :<, row.total
    assert_in_delta Time.current, row.last_at, 5.seconds
  end

  test "meals from recurring rules don't count as planned by hand" do
    before, rules_before = usage("Meals planned by hand").total, usage("Recurring meals").total
    rule = @household.recurring_meals.create!(meal_name: "Dinner", recipe: recipes(:one), user: users(:one),
                                              start_date: Date.current, pattern_type: "interval", interval_days: 1)
    @household.meals.create!(date: Date.current, meal_name: "Dinner", recipe: recipes(:one), user: users(:one), recurring_meal: rule)
    @household.meals.create!(date: Date.current, meal_name: "Lunch", recipe: recipes(:one), user: users(:one))

    assert_equal before + 1, usage("Meals planned by hand").total
    assert_equal rules_before + 1, usage("Recurring meals").total
  end

  test "restock is about items checked off, not the seeded list" do
    item = @household.restock_items.first || @household.restock_items.create!(name: "Milk", user: users(:one))
    assert_equal 0, usage("Restock items (checked lately)").recent

    item.update_columns(last_date_checked_stocked: 1.day.ago)
    row = usage("Restock items (checked lately)")
    assert_equal 1, row.recent
    assert_in_delta 1.day.ago, row.last_at, 5.seconds
  end

  test "nothing used shows as never" do
    row = usage("Receipt scans")
    assert_equal [ 0, 0, nil ], [ row.total, row.recent, row.last_at ]
  end
end
