require "test_helper"

class MealAssignmentTest < ActiveSupport::TestCase
  setup do
    @household = households(:one) # family size 3
    @meal  = meals(:one)
    @alice = household_members(:alice)
    @bob   = household_members(:one)
  end

  test "an unassigned meal is shared by the whole family" do
    assert_in_delta 1.0 / 3, @meal.share_for(@alice)
    assert_in_delta 1.0 / 3, @meal.share_for(@bob)
    assert_equal 1.0, @meal.share_for(nil), "the household as a whole ate all of it"
  end

  test "an assigned meal is split among the people assigned only" do
    @meal.update!(eater_ids: [ @bob.id ])
    assert_equal 1.0, @meal.reload.share_for(@bob)
    assert_equal 0.0, @meal.share_for(@alice)

    @meal.update!(eater_ids: [ @bob.id, @alice.id ])
    assert_equal 0.5, @meal.reload.share_for(@alice)
  end

  test "members of another household can't be assigned" do
    assignment = @meal.meal_assignments.build(household_member: household_members(:carol))
    assert_not assignment.valid?
  end

  test "removing a member removes their meal assignments" do
    @meal.update!(eater_ids: [ @bob.id ])
    @bob.destroy!
    assert_empty @meal.reload.meal_assignments
  end

  test "recurring meals copy who's eating and default servings to the family size" do
    rule = @household.recurring_meals.create!(
      user: users(:one), recipe: recipes(:one), meal_name: "Breakfast", pattern_type: "interval",
      interval_days: 1, start_date: Date.new(2026, 1, 5), end_type: "week", eater_ids: [ @bob.id ]
    )

    meals = rule.materialize_week!(Date.new(2026, 1, 5))

    assert meals.any?
    assert(meals.all? { |m| m.eater_ids == [ @bob.id ] })
    assert(meals.all? { |m| m[:servings] == 3 })
  end
end
