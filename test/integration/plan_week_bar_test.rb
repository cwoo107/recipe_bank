require "test_helper"

class PlanWeekBarTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, household :one
    @week = Date.current.beginning_of_week
  end

  test "does not show when nothing is currently being planned" do
    get todos_url
    assert_select "form[action=?]", plan_week_step_path(section: "meals", week: @week), count: 0
  end

  test "shows the continue/skip bar on an unrelated page while a plan is in progress" do
    WeeklyPlan.current_for(households(:one)).update!(currently_planning: true)

    get todos_url
    assert_select "form[action=?] input[name=status][value=done]", plan_week_step_path(section: "meals", week: @week)
    assert_select "form[action=?] input[name=status][value=skipped]", plan_week_step_path(section: "meals", week: @week)
  end

  test "advances to the next active section as steps complete" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.section("meals").mark!("done", by: users(:one))
    plan.update!(currently_planning: true)

    get todos_url
    assert_select "form[action=?] input[name=status][value=done]", plan_week_step_path(section: "restock", week: @week)
  end

  test "is suppressed on the wizard itself" do
    WeeklyPlan.current_for(households(:one)).update!(currently_planning: true)

    get plan_week_step_url(section: "meals")
    # The step page has its own Continue/Skip forms — just make sure we didn't double-render the bar.
    assert_select "#plan_week_bar", count: 0
  end

  test "is suppressed on the dashboard" do
    WeeklyPlan.current_for(households(:one)).update!(currently_planning: true)

    get dashboard_url
    assert_select "#plan_week_bar", count: 0
  end

  test "the sticky bar elsewhere in the app names the week and can be closed" do
    next_week = @week + 7
    WeeklyPlan.current_for(households(:one), week_start: next_week)
              .update!(currently_planning: true, planning_started_at: Time.current)

    get todos_url

    assert_select "#plan_week_bar" do
      assert_select "p", text: /Planning next week/
      assert_select "form[action='#{plan_week_path}'] input[name=_method][value=delete]"
      assert_select "form[action='#{plan_week_step_path(section: "meals", week: next_week)}']"
    end
  end

  test "closing the bar ends the session and sends you back where you were" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.update!(currently_planning: true, planning_started_at: Time.current)
    plan.section("meals").mark!("done", by: users(:one))

    delete plan_week_url, headers: { "HTTP_REFERER" => todos_url }
    assert_redirected_to todos_url

    refute plan.reload.currently_planning?
    assert plan.section("meals").done?, "closing keeps progress"

    get todos_url
    assert_select "#plan_week_bar", count: 0
  end

  test "after closing, the dashboard offers to continue planning that week" do
    next_week = @week + 7
    plan = WeeklyPlan.current_for(households(:one), week_start: next_week)
    plan.update!(currently_planning: true, planning_started_at: Time.current)
    plan.section("meals").mark!("done", by: users(:one))

    delete plan_week_url
    get dashboard_url

    assert_select "p", text: /partway through planning\s+next week/
    assert_select "a[href='#{plan_week_path(week: next_week)}']", text: "Continue planning"

    get plan_week_url(week: next_week)
    assert_redirected_to plan_week_step_url(section: "restock", week: next_week)
  end

  test "the dashboard doesn't offer to continue a finished plan" do
    WeeklyPlan.current_for(households(:one))
              .update!(planning_started_at: 10.minutes.ago, planning_completed_at: 1.minute.ago)

    get dashboard_url
    assert_select "a", text: "Continue planning", count: 0
  end
end
