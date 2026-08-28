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

  test "destroying a rule with remove_upcoming=0 leaves meals it already created on the calendar" do
    meal = @rule.materialize_week!(Date.new(2026, 1, 4)).first

    assert_difference("RecurringMeal.count", -1) do
      delete recurring_meal_url(@rule), params: { remove_upcoming: "0" }
    end

    assert_redirected_to recurring_meals_url
    assert Meal.exists?(meal.id)
    assert_nil meal.reload.recurring_meal_id
  end

  test "destroying a rule with remove_upcoming=1 removes future meals but keeps past ones" do
    rule = RecurringMeal.create!(household: households(:one), user: users(:one), recipe: recipes(:one),
                                  meal_name: "Dinner", pattern_type: "interval", interval_days: 1,
                                  start_date: Date.current - 10, end_type: "ongoing")
    rule.materialize_week!((Date.current - 10).beginning_of_week)
    rule.materialize_week!(Date.current.beginning_of_week)

    past_meal = rule.meals.where("date < ?", Date.current).first
    upcoming_meal = rule.meals.where("date >= ?", Date.current).first
    assert past_meal, "expected a past meal to have been generated"
    assert upcoming_meal, "expected an upcoming meal to have been generated"

    assert_difference("RecurringMeal.count", -1) do
      delete recurring_meal_url(rule), params: { remove_upcoming: "1" }
    end

    assert_redirected_to recurring_meals_url
    assert Meal.exists?(past_meal.id), "past meal should be kept"
    assert_not Meal.exists?(upcoming_meal.id), "upcoming meal should be removed"
  end

  test "a user in a different household cannot edit another household's recurring meal" do
    sign_in users(:three) # carol, household :two

    get edit_recurring_meal_url(@rule)
    assert_response :not_found
  end
end
