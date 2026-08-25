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
end
