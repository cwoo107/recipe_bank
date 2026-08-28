require "test_helper"

class RecurringMealOccurrenceTest < ActiveSupport::TestCase
  test "date must be unique per recurring meal" do
    existing = recurring_meal_occurrences(:one)
    dupe = RecurringMealOccurrence.new(recurring_meal: existing.recurring_meal, date: existing.date)

    assert_not dupe.valid?
    assert_includes dupe.errors[:date], "has already been taken"
  end

  test "surviving as a tombstone after its meal is destroyed" do
    occurrence = recurring_meal_occurrences(:one)
    meal = occurrence.meal
    meal.destroy!

    assert_nil occurrence.reload.meal_id
  end
end
