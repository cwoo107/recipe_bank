require "test_helper"

class NoteMealTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @date      = Date.new(2026, 1, 7)
  end

  def note_meal(**attrs)
    @household.meals.create!(user: users(:one), note: "Eating out", meal_name: "Dinner", date: @date, **attrs)
  end

  test "needs a recipe or a note" do
    meal = @household.meals.build(user: users(:one), meal_name: "Dinner", date: @date)
    assert_not meal.valid?
    assert_match "write a note", meal.errors.full_messages.to_sentence
  end

  test "has no nutrition or cost" do
    meal = note_meal
    assert_equal 0, meal.scaled_calories
    assert_equal 0, meal.scaled_protein
    assert_equal 0, meal.total_cost
  end

  test "week stats leave it out but still take its eaters out of the shared meal" do
    member = @household.household_members.first
    note   = note_meal(eater_ids: [ member.id ])
    shared = meals(:one) # Dinner the same day, nobody assigned

    stats = MealWeekStats.new([ note, shared ], member: member)
    assert_empty stats.rows
  end
end
