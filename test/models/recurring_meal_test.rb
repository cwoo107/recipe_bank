require "test_helper"

class RecurringMealTest < ActiveSupport::TestCase
  test "occurs_on? matches specific weekdays" do
    rule = recurring_meals(:one) # days_of_week [0] (Sunday), start_date 2026-01-01, no end
    assert rule.occurs_on?(Date.new(2026, 1, 4))  # Sunday
    assert_not rule.occurs_on?(Date.new(2026, 1, 5)) # Monday
  end

  test "occurs_on? respects start and end date bounds" do
    rule = recurring_meals(:two) # interval every day, 2026-01-01..2026-01-07
    assert_not rule.occurs_on?(Date.new(2025, 12, 31))
    assert rule.occurs_on?(Date.new(2026, 1, 1))
    assert rule.occurs_on?(Date.new(2026, 1, 7))
    assert_not rule.occurs_on?(Date.new(2026, 1, 8))
  end

  test "occurs_on? matches an interval pattern" do
    rule = RecurringMeal.new(pattern_type: "interval", interval_days: 2, start_date: Date.new(2026, 1, 1))
    assert rule.occurs_on?(Date.new(2026, 1, 1))
    assert_not rule.occurs_on?(Date.new(2026, 1, 2))
    assert rule.occurs_on?(Date.new(2026, 1, 3))
  end

  test "end_type week resolves end_date to the end of the start date's week" do
    rule = RecurringMeal.new(start_date: Date.new(2026, 1, 5), end_type: "week") # Monday
    rule.valid?
    assert_equal Date.new(2026, 1, 5).end_of_week, rule.end_date
  end

  test "end_type ongoing clears end_date" do
    rule = RecurringMeal.new(start_date: Date.new(2026, 1, 5), end_date: Date.new(2026, 1, 10), end_type: "ongoing")
    rule.valid?
    assert_nil rule.end_date
  end

  test "requires days_of_week when pattern_type is days_of_week" do
    rule = RecurringMeal.new(household: households(:one), user: users(:one), recipe: recipes(:one),
                              meal_name: "Dinner", pattern_type: "days_of_week", start_date: Date.today)
    assert_not rule.valid?
    assert_includes rule.errors[:days_of_week], "can't be blank"
  end

  test "requires a positive interval when pattern_type is interval" do
    rule = RecurringMeal.new(household: households(:one), user: users(:one), recipe: recipes(:one),
                              meal_name: "Dinner", pattern_type: "interval", interval_days: 0, start_date: Date.today)
    assert_not rule.valid?
    assert_includes rule.errors[:interval_days], "must be greater than 0"
  end

  test "materialize_week! is idempotent and only creates meals for matching dates" do
    rule = recurring_meals(:one) # Sundays only, household :one
    week_start = Date.new(2026, 1, 4) # a Sunday

    assert_difference("Meal.count", 1) do
      created = rule.materialize_week!(week_start)
      assert_equal [Date.new(2026, 1, 4)], created.map(&:date)
    end

    assert_no_difference("Meal.count") do
      assert_empty rule.materialize_week!(week_start)
    end
  end

  test "materialize_week! skips a date that already has an occurrence" do
    rule = recurring_meals(:one)
    occurrence = recurring_meal_occurrences(:one) # date 2026-01-11, a Sunday already tombstoned
    assert_no_difference("RecurringMealOccurrence.count") do
      assert_empty rule.materialize_week!(occurrence.date.beginning_of_week)
    end
  end

  test "destroying the rule nullifies recurring_meal_id on meals it created but leaves them intact" do
    rule = recurring_meals(:one)
    created = rule.materialize_week!(Date.new(2026, 1, 4))
    meal = created.first

    rule.destroy!

    assert Meal.exists?(meal.id)
    assert_nil meal.reload.recurring_meal_id
  end
end
