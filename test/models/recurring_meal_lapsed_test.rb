require "test_helper"

class RecurringMealLapsedTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @household.update!(time_zone: "America/Boise")
  end

  def rule(start_date:, end_date:)
    RecurringMeal.create!(household: @household, user: users(:one), recipe: recipes(:one), meal_name: "Dinner",
                          pattern_type: "interval", interval_days: 1, start_date: start_date,
                          end_type: end_date ? "date" : "ongoing", end_date: end_date)
  end

  test "deletes rules that ended before today, keeping the meals they scheduled" do
    travel_to Time.utc(2026, 11, 10, 18) do # Nov 10 in Boise
      ended    = rule(start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 9))
      today    = rule(start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 10))
      ongoing  = rule(start_date: Date.new(2026, 11, 2), end_date: nil)
      meal = ended.materialize_week!(Date.new(2026, 11, 2)).first

      # (Fixture rules that have ended go too.)
      assert_equal RecurringMeal.all.count(&:lapsed?), RecurringMeal.delete_lapsed!

      assert_not RecurringMeal.exists?(ended.id)
      assert RecurringMeal.exists?(today.id)
      assert RecurringMeal.exists?(ongoing.id)
      assert Meal.exists?(meal.id), "the meal stays on the calendar"
      assert_nil meal.reload.recurring_meal_id
    end
  end

  test "goes by the household's own date" do
    # 20:00 UTC on Nov 9: still Nov 9 in Boise, already Nov 10 in Tokyo.
    travel_to Time.utc(2026, 11, 9, 20) do
      boise = rule(start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 9))

      tokyo_household = households(:two)
      tokyo_household.update!(time_zone: "Asia/Tokyo")
      tokyo = RecurringMeal.create!(household: tokyo_household, user: users(:three), recipe: recipes(:two), meal_name: "Dinner",
                                    pattern_type: "interval", interval_days: 1, start_date: Date.new(2026, 11, 2),
                                    end_type: "date", end_date: Date.new(2026, 11, 9))

      assert_not boise.lapsed?
      assert tokyo.lapsed?

      RecurringMeal.delete_lapsed!
      assert RecurringMeal.exists?(boise.id)
      assert_not RecurringMeal.exists?(tokyo.id)
    end
  end

  test "the daily job runs it" do
    travel_to Time.utc(2026, 11, 10, 18) do
      ended = rule(start_date: Date.new(2026, 11, 2), end_date: Date.new(2026, 11, 9))

      DeleteLapsedRecurringMealsJob.perform_now
      assert_not RecurringMeal.exists?(ended.id)
      assert_empty RecurringMeal.all.select(&:lapsed?)
    end
  end
end
