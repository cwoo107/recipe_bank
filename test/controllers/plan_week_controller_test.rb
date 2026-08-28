require "test_helper"

class PlanWeekControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, household :one
  end

  test "start resumes at the first incomplete section" do
    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "meals")
  end

  test "resumes past sections already marked done or skipped" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.section("meals").mark!("done", by: users(:one))
    plan.section("groceries").mark!("skipped", by: users(:one))

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "chores")
  end

  test "reopening a fully completed week is never blocked" do
    plan = WeeklyPlan.current_for(households(:one))
    %w[meals todos groceries chores calendar].each { |k| plan.section(k).mark!("done", by: users(:one)) }

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "meals")
  end

  test "each step is reachable directly, not just from the start of the wizard" do
    get plan_week_step_url(section: "groceries")
    assert_response :success
  end

  test "update marks a section and advances to the next incomplete one" do
    patch plan_week_step_url(section: "meals"), params: { status: "done" }
    assert_redirected_to plan_week_step_url(section: "groceries")

    plan = WeeklyPlan.current_for(households(:one))
    assert plan.section("meals").done?
  end

  test "update on the last section redirects to the dashboard" do
    plan = WeeklyPlan.current_for(households(:one))
    %w[meals todos groceries].each { |k| plan.section(k).mark!("done", by: users(:one)) }

    patch plan_week_step_url(section: "calendar"), params: { status: "done" }
    assert_redirected_to dashboard_url
  end

  test "skip marks the section skipped" do
    patch plan_week_step_url(section: "todos"), params: { status: "skipped" }

    plan = WeeklyPlan.current_for(households(:one))
    assert plan.section("todos").skipped?
  end

  test "groceries step tells you to plan meals first when meals aren't planned" do
    get plan_week_step_url(section: "groceries")
    assert_select "a", text: "Plan meals"
  end

  test "chores step lists chores that are due and not yet on this week's list" do
    get plan_week_step_url(section: "chores")
    assert_response :success
    assert_select "button", text: "Add to this week"
  end

  test "visiting any step marks the plan as currently planning" do
    plan = WeeklyPlan.current_for(households(:one))
    refute plan.currently_planning?

    get plan_week_step_url(section: "meals")
    assert plan.reload.currently_planning?
  end

  test "finishing the wizard turns currently_planning back off" do
    plan = WeeklyPlan.current_for(households(:one))
    %w[meals todos groceries].each { |k| plan.section(k).mark!("done", by: users(:one)) }
    plan.update!(currently_planning: true)

    patch plan_week_step_url(section: "calendar"), params: { status: "done" }
    refute plan.reload.currently_planning?
  end

  test "starting the wizard stamps planning_started_at" do
    plan = WeeklyPlan.current_for(households(:one))
    assert_nil plan.planning_started_at

    get plan_week_step_url(section: "meals")
    assert_not_nil plan.reload.planning_started_at
  end

  test "finishing the wizard stamps planning_completed_at and flashes elapsed time" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.update!(currently_planning: true, planning_started_at: 3.minutes.ago)
    %w[meals todos groceries].each { |k| plan.section(k).mark!("done", by: users(:one)) }

    patch plan_week_step_url(section: "calendar"), params: { status: "done" }

    assert_not_nil plan.reload.planning_completed_at
    assert_match(/Congrats! It just took you 3 minutes to plan your week\./, flash[:notice])
  end
end
