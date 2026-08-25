require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "signed-in root redirects to the dashboard" do
    sign_in users(:one)
    get root_url
    assert_redirected_to dashboard_url
  end

  test "shows an empty-state card for a household with nothing planned this week" do
    sign_in users(:three) # carol, household :two has no data for the current week

    get dashboard_url
    assert_response :success
    assert_select "a", text: "Plan your week"
  end

  test "shows a real summary for a household with data this week" do
    household = households(:one)
    household.meals.create!(user: users(:one), recipe: recipes(:one), meal_name: "Dinner",
                             date: Date.current.beginning_of_week, servings: 4)

    sign_in users(:one)
    get dashboard_url
    assert_response :success
    assert_select "p", text: /1 of 7 dinners planned/
  end

  test "landing on the dashboard turns off currently_planning" do
    sign_in users(:one)
    plan = WeeklyPlan.current_for(households(:one))
    plan.update!(currently_planning: true)

    get dashboard_url
    refute plan.reload.currently_planning?
  end
end
