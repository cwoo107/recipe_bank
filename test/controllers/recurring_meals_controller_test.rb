require "test_helper"

class RecurringMealsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @rule = recurring_meals(:one) # household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get recurring_meals_url
    assert_response :success
  end

  test "index only lists the current household's recurring meals" do
    get recurring_meals_url
    assert_match @rule.meal_name, response.body
    assert_no_match(/#{recurring_meals(:two).meal_name}/, response.body)
  end

  test "should get edit" do
    get edit_recurring_meal_url(@rule)
    assert_response :success
  end

  test "should update recurring meal" do
    patch recurring_meal_url(@rule), params: {
      recurring_meal: { recipe_id: @rule.recipe_id, meal_name: @rule.meal_name,
                         pattern_type: "interval", interval_days: 3,
                         start_date: @rule.start_date, end_type: "ongoing" }
    }
    assert_redirected_to recurring_meals_url
    assert_equal "interval", @rule.reload.pattern_type
    assert_equal 3, @rule.interval_days
  end

  test "destroying a rule leaves meals it already created on the calendar" do
    meal = @rule.materialize_week!(Date.new(2026, 1, 4)).first

    assert_difference("RecurringMeal.count", -1) do
      delete recurring_meal_url(@rule)
    end

    assert_redirected_to recurring_meals_url
    assert Meal.exists?(meal.id)
    assert_nil meal.reload.recurring_meal_id
  end

  test "a user in a different household cannot edit another household's recurring meal" do
    sign_in users(:three) # carol, household :two

    get edit_recurring_meal_url(@rule)
    assert_response :not_found
  end
end
