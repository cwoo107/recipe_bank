require "test_helper"

class MealsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @meal = meals(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get meals_url
    assert_response :success
  end

  test "should get new" do
    get new_meal_url
    assert_response :success
  end

  test "should create meal" do
    assert_difference("Meal.count") do
      post meals_url, params: { meal: { date: @meal.date, meal_name: @meal.meal_name, recipe_id: @meal.recipe_id } }
    end

    assert_equal households(:one), Meal.last.household
    assert_redirected_to meals_url
  end

  test "should show meal" do
    get meal_url(@meal)
    assert_response :success
  end

  test "should get edit" do
    get edit_meal_url(@meal)
    assert_response :success
  end

  test "should update meal" do
    patch meal_url(@meal), params: { meal: { date: @meal.date, meal_name: @meal.meal_name, recipe_id: @meal.recipe_id } }
    assert_redirected_to meal_url(@meal)
  end

  test "should destroy meal" do
    assert_difference("Meal.count", -1) do
      delete meal_url(@meal)
    end

    assert_redirected_to meals_url(date: @meal.date.beginning_of_week)
  end

  test "another member of the same household can see the meal" do
    sign_in users(:two) # bob, also in household :one

    get meal_url(@meal)
    assert_response :success
  end

  test "a user in a different household cannot see the meal" do
    sign_in users(:three) # carol, household :two

    get meal_url(@meal)
    assert_response :not_found
  end

  test "should create a recurring meal and materialize the current week" do
    assert_difference("RecurringMeal.count", 1) do
      post meals_url, params: {
        meal: {
          recipe_id: @meal.recipe_id, meal_name: "Dinner",
          recurring: { enabled: "1", pattern_type: "days_of_week", days_of_week: ["0"],
                       start_date: "2026-01-01", end_type: "ongoing" }
        }
      }
    end

    rule = RecurringMeal.last
    assert_equal households(:one), rule.household
    assert_redirected_to meals_url(date: Date.new(2026, 1, 1).beginning_of_week)
    assert rule.meals.exists?(date: Date.new(2026, 1, 4)) # the first Sunday on/after start_date
  end

  test "updating a generated meal detaches it from its recurring rule" do
    rule = recurring_meals(:one)
    meal = rule.materialize_week!(Date.new(2026, 1, 4)).first
    assert_not_nil meal.recurring_meal_id

    patch meal_url(meal), params: { meal: { date: meal.date, meal_name: meal.meal_name, recipe_id: meal.recipe_id } }

    assert_nil meal.reload.recurring_meal_id
  end

  test "index materializes recurring meals for the requested week" do
    rule = recurring_meals(:one) # Sundays, household :one
    week_start = Date.new(2026, 1, 4).beginning_of_week

    assert_difference("Meal.count", 1) do
      get meals_url(date: week_start)
    end
    assert_response :success
    assert rule.meals.exists?(date: Date.new(2026, 1, 4))
  end
end
