require "test_helper"

class PlanWeekBarTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, household :one
  end

  test "does not show when nothing is currently being planned" do
    get todos_url
    assert_select "form[action=?]", plan_week_step_path(section: "meals"), count: 0
  end

  test "shows the continue/skip bar on an unrelated page while a plan is in progress" do
    WeeklyPlan.current_for(households(:one)).update!(currently_planning: true)

    get todos_url
    assert_select "form[action=?] input[name=status][value=done]", plan_week_step_path(section: "meals")
    assert_select "form[action=?] input[name=status][value=skipped]", plan_week_step_path(section: "meals")
  end

  test "advances to the next active section as steps complete" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.section("meals").mark!("done", by: users(:one))
    plan.update!(currently_planning: true)

    get todos_url
    assert_select "form[action=?] input[name=status][value=done]", plan_week_step_path(section: "groceries")
  end

  test "is suppressed on the wizard itself" do
    WeeklyPlan.current_for(households(:one)).update!(currently_planning: true)

    get plan_week_step_url(section: "meals")
    # The step page has its own Continue/Skip forms — just make sure we didn't double-render the bar.
    assert_select "div.fixed.bottom-4.right-4", count: 0
  end

  test "is suppressed on the dashboard" do
    WeeklyPlan.current_for(households(:one)).update!(currently_planning: true)

    get dashboard_url
    assert_select "div.fixed.bottom-4.right-4", count: 0
  end
end
