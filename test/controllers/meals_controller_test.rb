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

  test "index shows detailed meal cards by default" do
    get meals_url(date: @meal.date.beginning_of_week)

    assert_response :success
    assert_select "#meal_#{@meal.id}", text: /cal\/serving/
    assert_select "button[role=switch][aria-checked=false]", text: /Compact view/
  end

  test "index hides meal details when compact view is on" do
    users(:one).update!(compact_meals_view: true)

    get meals_url(date: @meal.date.beginning_of_week)

    assert_response :success
    assert_select "#meal_#{@meal.id}", text: /#{Regexp.escape(@meal.recipe.title)}/
    assert_select "#meal_#{@meal.id}", text: /cal\/serving|ingredients|protein|per serving/, count: 0
    assert_select "button[role=switch][aria-checked=true]", text: /Compact view/
  end

  test "each meal card has an Edit button that loads the meal form in a modal" do
    get meals_url(date: @meal.date.beginning_of_week)

    assert_select "#meal_#{@meal.id} dialog turbo-frame#edit_meal_#{@meal.id}[src='#{edit_meal_path(@meal)}'][loading=lazy]"
    assert_select "#meal_#{@meal.id} button", text: "Edit"
  end

  test "the edit form renders inside the modal's frame" do
    get edit_meal_url(@meal), headers: { "Turbo-Frame" => "edit_meal_#{@meal.id}" }

    assert_select "turbo-frame#edit_meal_#{@meal.id} form[action='#{meal_path(@meal)}']"
  end

  test "saving from the Edit modal refreshes the meals page in place" do
    patch meal_url(@meal), params: { meal: { servings: 2 } },
          headers: { "Turbo-Frame" => "edit_meal_#{@meal.id}", "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :success
    assert_select "turbo-stream[action=refresh]"
    assert_equal 2, @meal.reload[:servings]
  end

  test "a failed save from the Edit modal shows errors in the modal" do
    patch meal_url(@meal), params: { meal: { meal_name: "Brunch" } },
          headers: { "Turbo-Frame" => "edit_meal_#{@meal.id}", "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#edit_meal_#{@meal.id} form"
  end

  test "a recurring meal added while planning a future week starts at that week" do
    travel_to Date.new(2026, 1, 7) # Wednesday; this week began Mon Jan 5

    get meals_url(date: "2026-01-19")
    assert_select "turbo-frame#new_meal[src='#{new_meal_path(week: Date.new(2026, 1, 19))}']"

    get new_meal_url(week: "2026-01-19")
    assert_select "input[name='meal[recurring][start_date]'][value='2026-01-19']"
    assert_select "input[name='meal[date]'][value='2026-01-19']"
    assert_select "[data-week-date-picker-selected-value='2026-01-19'][data-week-date-picker-week-start-value='2026-01-19']"
  end

  test "a recurring meal added this week starts today, not earlier in the week" do
    travel_to Date.new(2026, 1, 7)

    get new_meal_url(week: "2026-01-05")
    assert_select "input[name='meal[recurring][start_date]'][value='2026-01-07']"
    assert_select "[data-week-date-picker-selected-value='2026-01-07'][data-week-date-picker-week-start-value='2026-01-05']"
  end

  test "a recurring meal added from a day's cell starts on that day" do
    get new_meal_url(date: "2026-01-21", meal_name: "Dinner")
    assert_select "input[name='meal[recurring][start_date]'][value='2026-01-21']"
  end

  test "adding from a slot pre-selects that slot's meal type" do
    get new_meal_url(date: "2026-01-21", meal_name: "Dinner")
    assert_select "input[type=radio][name='meal[meal_name]'][value=Dinner][checked]"
    assert_select "input[type=radio][name='meal[meal_name]'][checked]", count: 1

    get new_meal_url(date: "2026-01-19", meal_name: "Snack")
    assert_select "input[type=radio][name='meal[meal_name]'][value=Snack][checked]"
  end

  test "the edit form pre-selects the meal's own type" do
    get edit_meal_url(@meal) # a Dinner
    assert_select "input[type=radio][name='meal[meal_name]'][value=Dinner][checked]"
  end

  test "a new meal with no slot defaults to breakfast" do
    get new_meal_url
    assert_select "input[type=radio][name='meal[meal_name]'][value=Breakfast][checked]"
  end

  test "every slot keeps an add button, including ones that already have a meal" do
    get meals_url(date: "2026-01-05") # @meal is Wednesday (day 2) dinner

    assert_select ".group\\/cell:has(#desktop_cell_2_dinner #meal_#{@meal.id})" do
      assert_select "turbo-frame#new_meal[src='#{new_meal_path(date: '2026-01-07', meal_name: 'Dinner')}']"
      assert_select "button[aria-label='Add dinner for Jan 07']", count: 2 # placeholder + compact; CSS picks one
    end
    assert_select "button[aria-label='Add a snack this week']"
    assert_select "button[aria-label='Add a dessert this week']"
  end

  test "adding a meal to a slot no longer removes its add button" do
    post meals_url, params: { meal: { recipe_id: recipes(:one).id, meal_name: "Lunch", date: "2026-01-06" } },
                    as: :turbo_stream

    assert_no_match(/turbo-stream action="remove" target="empty_cell/, response.body)
    assert_match(/turbo-stream action="append" target="desktop_cell_1_lunch"/, response.body)
  end
end
