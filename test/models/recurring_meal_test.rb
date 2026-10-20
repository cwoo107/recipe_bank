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

  # Mon/Wed/Fri dinners, materialized for two weeks (Jan 5 – 18, 2026).
  def build_weekly_rule(days: [ 1, 3, 5 ])
    rule = households(:one).recurring_meals.create!(user: users(:one), recipe: recipes(:one), meal_name: "Dinner",
                                                    pattern_type: "days_of_week", days_of_week: days,
                                                    start_date: Date.new(2026, 1, 5), end_date: Date.new(2026, 1, 31))
    rule.materialize_week!(Date.new(2026, 1, 5))
    rule.materialize_week!(Date.new(2026, 1, 12))
    rule
  end

  test "move_sequence! swaps the dragged weekday and moves later meals with it" do
    rule = build_weekly_rule
    wed = rule.meals.find_by!(date: Date.new(2026, 1, 7))

    rule.move_sequence!(wed, to_date: Date.new(2026, 1, 8), to_meal_name: "Lunch")

    assert_equal [ 1, 4, 5 ], rule.reload.days_of_week
    assert_equal "Lunch", rule.meal_name
    assert_equal [ Date.new(2026, 1, 8), "Lunch" ], [ wed.reload.date, wed.meal_name ]

    # Earlier meals stay as they were; later ones follow the new shape.
    assert_equal "Dinner", rule.meals.find_by!(date: Date.new(2026, 1, 5)).meal_name
    later = rule.meals.where(date: Date.new(2026, 1, 9)..).order(:date).pluck(:date, :meal_name)
    assert_equal [ [ Date.new(2026, 1, 9), "Lunch" ], [ Date.new(2026, 1, 12), "Lunch" ],
                   [ Date.new(2026, 1, 15), "Lunch" ], [ Date.new(2026, 1, 16), "Lunch" ] ], later
    assert_not rule.recurring_meal_occurrences.exists?(date: Date.new(2026, 1, 14))

    # Nothing regenerates on the old weekday.
    assert_empty rule.materialize_week!(Date.new(2026, 1, 12))
  end

  test "move_sequence! drops the duplicates when the new weekday is already in the rule" do
    rule = build_weekly_rule(days: [ 1, 2 ])
    mon = rule.meals.find_by!(date: Date.new(2026, 1, 5))

    rule.move_sequence!(mon, to_date: Date.new(2026, 1, 6), to_meal_name: "Dinner")

    assert_equal [ 2 ], rule.reload.days_of_week
    # This week keeps both (the dragged one went where it was put); next week has one.
    assert_equal 2, rule.meals.where(date: Date.new(2026, 1, 6)).count
    assert_equal [ Date.new(2026, 1, 13) ], rule.meals.where(date: Date.new(2026, 1, 12)..).pluck(:date)
  end

  test "move_sequence! shifts an interval rule's cycle" do
    rule = households(:one).recurring_meals.create!(user: users(:one), recipe: recipes(:one), meal_name: "Dinner",
                                                    pattern_type: "interval", interval_days: 3,
                                                    start_date: Date.new(2026, 1, 5), end_date: Date.new(2026, 1, 31))
    rule.materialize_week!(Date.new(2026, 1, 5)) # Jan 5, 8, 11
    eighth = rule.meals.find_by!(date: Date.new(2026, 1, 8))

    rule.move_sequence!(eighth, to_date: Date.new(2026, 1, 9), to_meal_name: "Dinner")

    assert_equal Date.new(2026, 1, 6), rule.reload.start_date
    assert_equal [ Date.new(2026, 1, 5), Date.new(2026, 1, 9), Date.new(2026, 1, 12) ], rule.meals.order(:date).pluck(:date)
  end

  test "move_sequence! on a daily rule only changes the meal type" do
    rule = households(:one).recurring_meals.create!(user: users(:one), recipe: recipes(:one), meal_name: "Dinner",
                                                    pattern_type: "interval", interval_days: 1,
                                                    start_date: Date.new(2026, 1, 5), end_date: Date.new(2026, 1, 11))
    rule.materialize_week!(Date.new(2026, 1, 5))
    wed = rule.meals.find_by!(date: Date.new(2026, 1, 7))

    rule.move_sequence!(wed, to_date: Date.new(2026, 1, 8), to_meal_name: "Lunch")

    assert_equal Date.new(2026, 1, 5), rule.reload.start_date
    assert_equal "Lunch", rule.meal_name
    assert_equal %w[Dinner Dinner Lunch Lunch Lunch Lunch Lunch], rule.meals.order(:date, :id).pluck(:meal_name)
    assert_empty rule.materialize_week!(Date.new(2026, 1, 5)) # Wed isn't regenerated
  end
end
