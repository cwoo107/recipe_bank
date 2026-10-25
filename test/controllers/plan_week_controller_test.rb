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
    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)
  end

  test "resumes past sections already marked done or skipped" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.section("calendar").mark!("done", by: users(:one))
    plan.section("meals").mark!("done", by: users(:one))
    plan.section("restock").mark!("done", by: users(:one))
    plan.section("groceries").mark!("skipped", by: users(:one))

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "chores", week: @this_week)
  end

  test "reopening a fully completed week is never blocked" do
    complete_all(WeeklyPlan.current_for(households(:one)))

    get plan_week_url(week: @this_week)
    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)
  end

  test "once this week is planned, planning moves on to next week" do
    complete_all(WeeklyPlan.current_for(households(:one)))

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "calendar", week: @next_week)
  end

  test "a finished wizard counts as planned even with steps left open" do
    WeeklyPlan.current_for(households(:one)).update!(planning_completed_at: 1.day.ago)

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "calendar", week: @next_week)
  end

  test "an in-progress week is resumed ahead of the default" do
    WeeklyPlan.current_for(households(:one), week_start: @next_week + 7).update!(currently_planning: true)

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "calendar", week: @next_week + 7)
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
    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)

    get plan_week_url(week: @this_week + (7 * (WeeklyPlan::WEEKS_AHEAD + 1)))
    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)

    get plan_week_url(week: "not-a-date")
    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)
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
    %w[calendar meals groceries].each { |k| plan.section(k).mark!("done", by: users(:one)) }

    patch plan_week_step_url(section: "todos"), params: { status: "done" }
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

  test "to-dos step asks about earlier weeks' to-dos and offers the To-Do column" do
    household = households(:one)
    left_over = household.todos.create!(user: users(:one), title: "Left over", priority: :medium,
                                        status: "in_progress", planned_week: @this_week - 7)
    get plan_week_step_url(section: "todos")

    assert_response :success
    assert_select "#todo_budget"
    assert_select "#carried_over_todos #plan_todo_#{left_over.id} button", text: "Mark complete"
    assert_select "#carried_over_todos #plan_todo_#{left_over.id} button", text: "Add to this week again"
    assert_select "#backlog_todos #plan_todo_#{todos(:one).id} button", text: "Add to this week"
  end

  test "visiting any step marks the plan as currently planning" do
    plan = WeeklyPlan.current_for(households(:one))
    refute plan.currently_planning?

    get plan_week_step_url(section: "meals")
    assert plan.reload.currently_planning?
  end

  test "finishing the wizard turns currently_planning back off" do
    plan = WeeklyPlan.current_for(households(:one))
    %w[calendar meals groceries].each { |k| plan.section(k).mark!("done", by: users(:one)) }
    plan.update!(currently_planning: true)

    patch plan_week_step_url(section: "todos"), params: { status: "done" }
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
    %w[calendar meals groceries].each { |k| plan.section(k).mark!("done", by: users(:one)) }

    patch plan_week_step_url(section: "todos"), params: { status: "done" }

    assert_not_nil plan.reload.planning_completed_at
    assert_match(/Congrats! It just took you 3 minutes to plan this week\./, flash[:notice])
  end

  # ── Mobile layout ──

  test "on mobile the steps are an accordion: the current one open, with its content between the others" do
    plan = WeeklyPlan.current_for(households(:one), week_start: @this_week)
    plan.section("meals").mark!("done", by: users(:one))

    get plan_week_step_url(section: "restock", week: @this_week)

    headers = css_select("a[aria-expanded]")
    keys    = headers.map { |a| a["href"][%r{/plan-week/([a-z]+)}, 1] }
    assert_equal households(:one).planner_section_keys, keys
    assert_equal [ "restock" ], headers.select { |a| a["aria-expanded"] == "true" }.map { |a| a["href"][%r{/plan-week/([a-z]+)}, 1] }

    # The step's content sits after the open header and before the next one —
    # rendered once, not per layout.
    body = response.body
    open_at    = body.index(%(aria-expanded="true"))
    content_at = body.index("Go to Restock Checklist")
    next_at    = body.index(plan_week_step_path(section: "groceries", week: @this_week), open_at)
    assert_operator open_at, :<, content_at
    assert_operator content_at, :<, next_at
  end

  test "the desktop step bar is hidden on mobile" do
    get plan_week_step_url(section: "meals", week: @this_week)
    assert_select "nav[aria-label=Progress].hidden.md\\:block"
  end

  test "mobile shows only the first three weeks to choose from" do
    get plan_week_step_url(section: "meals", week: @this_week)

    pills = css_select("nav[aria-label='Choose a week to plan'] li")
    assert_operator pills.size, :>, 3
    assert pills.first(3).none? { |li| li["class"].include?("hidden") }
    assert pills.drop(3).all? { |li| li["class"].include?("hidden sm:block") }
  end

  # ── The calendar step ──

  test "the calendar step is first and shows the week's events as a week grid" do
    source = households(:one).calendar_sources.create!(name: "Family", provider: "google", color: "seafoam",
                                                       ical_url: "https://calendar.example.com/feed.ics", user: users(:one))
    households(:one).calendar_events.create!(calendar_source: source, user: users(:one), title: "Soccer practice",
                                             starts_at: (@this_week + 2).in_time_zone.change(hour: 17),
                                             ends_at: (@this_week + 2).in_time_zone.change(hour: 18))
    households(:one).calendar_events.create!(calendar_source: source, user: users(:one), title: "Next week's thing",
                                             starts_at: (@next_week + 1).in_time_zone.change(hour: 9),
                                             ends_at: (@next_week + 1).in_time_zone.change(hour: 10))

    get plan_week_url
    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)
    follow_redirect!

    assert_select "a[href=?]", day_calendars_path(date: (@this_week + 2).to_s) # the grid's day headers
    assert_select "button", text: /Soccer practice/
    assert_select "button", text: /Next week's thing/, count: 0
    assert_select "a[href=?]", week_calendars_path(date: @this_week), text: "Go to Calendar"
  end
end
