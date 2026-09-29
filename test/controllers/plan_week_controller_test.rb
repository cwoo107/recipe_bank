require "test_helper"

class PlanWeekControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one) # alice, household :one
    @this_week = Date.current.beginning_of_week
    @next_week = @this_week + 7
  end

  def complete_all(plan)
    Dashboard.section_keys.each { |k| plan.section(k).mark!("done", by: users(:one)) }
  end

  test "start resumes at the first incomplete section" do
    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "meals", week: @this_week)
  end

  test "resumes past sections already marked done or skipped" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.section("meals").mark!("done", by: users(:one))
    plan.section("restock").mark!("done", by: users(:one))
    plan.section("groceries").mark!("skipped", by: users(:one))

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "chores", week: @this_week)
  end

  test "reopening a fully completed week is never blocked" do
    complete_all(WeeklyPlan.current_for(households(:one)))

    get plan_week_url(week: @this_week)
    assert_redirected_to plan_week_step_url(section: "meals", week: @this_week)
  end

  test "once this week is planned, planning moves on to next week" do
    complete_all(WeeklyPlan.current_for(households(:one)))

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "meals", week: @next_week)
  end

  test "a finished wizard counts as planned even with steps left open" do
    WeeklyPlan.current_for(households(:one)).update!(planning_completed_at: 1.day.ago)

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "meals", week: @next_week)
  end

  test "an in-progress week is resumed ahead of the default" do
    WeeklyPlan.current_for(households(:one), week_start: @next_week + 7).update!(currently_planning: true)

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "meals", week: @next_week + 7)
  end

  test "the step page says which week is being planned" do
    get plan_week_step_url(section: "meals", week: @next_week)

    assert_select "h2", text: /Next week/
    assert_select "nav[aria-label='Choose a week to plan'] a", count: WeeklyPlan::WEEKS_AHEAD + 1
    assert_select "nav[aria-label='Choose a week to plan'] a[aria-current='true']", text: /Next week/
  end

  test "switching weeks hands the planning session to the new week" do
    this_plan = WeeklyPlan.current_for(households(:one))
    this_plan.update!(currently_planning: true)

    get plan_week_url(week: @next_week)

    refute this_plan.reload.currently_planning?
    assert WeeklyPlan.current_for(households(:one), week_start: @next_week).currently_planning?
  end

  test "marking a step on another week only touches that week" do
    patch plan_week_step_url(section: "meals", week: @next_week), params: { status: "done" }
    assert_redirected_to plan_week_step_url(section: "restock", week: @next_week)

    assert WeeklyPlan.current_for(households(:one), week_start: @next_week).section("meals").done?
    refute WeeklyPlan.current_for(households(:one)).section("meals").done?
  end

  test "past or far-off weeks fall back to the week that needs planning" do
    get plan_week_url(week: @this_week - 7)
    assert_redirected_to plan_week_step_url(section: "meals", week: @this_week)

    get plan_week_url(week: @this_week + (7 * (WeeklyPlan::WEEKS_AHEAD + 1)))
    assert_redirected_to plan_week_step_url(section: "meals", week: @this_week)

    get plan_week_url(week: "not-a-date")
    assert_redirected_to plan_week_step_url(section: "meals", week: @this_week)
  end

  test "each step is reachable directly, not just from the start of the wizard" do
    get plan_week_step_url(section: "groceries")
    assert_response :success
  end

  test "update marks a section and advances to the next incomplete one" do
    patch plan_week_step_url(section: "meals"), params: { status: "done" }
    assert_redirected_to plan_week_step_url(section: "restock", week: @this_week)

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
    assert_select "#due_chores #due_chore_#{chores(:one).id}"
    assert_select "#due_chore_#{chores(:one).id} .sm\\:hidden button", text: "Add to this week"
    assert_select "#due_chore_#{chores(:one).id} dialog form[action*=scheduled_date]", 7
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
    assert_match(/Congrats! It just took you 3 minutes to plan this week\./, flash[:notice])
  end
end
