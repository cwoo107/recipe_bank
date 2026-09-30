require "test_helper"

# A household can leave planning areas it never uses out of "Plan your week"
# (Household#planner_section_keys). They stay in the app; they just aren't
# planner steps, and start unticked on the print page.
class PlannerSectionsTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @this_week = Date.current.beginning_of_week
    sign_in users(:one) # alice, admin
  end

  def leave_out(*keys)
    @household.update!(planner_sections: Dashboard.section_keys - keys)
  end

  # ── The setting ──

  test "the settings form lists every step, ticked by default" do
    get household_url

    Dashboard.sections.each do |section|
      assert_select "input[type=checkbox][name='household[planner_sections][]'][value=?][checked]", section::KEY
    end
  end

  test "unticking a step leaves it out of the planner" do
    patch household_url, params: { household: { planner_sections: [ "" ] + (Dashboard.section_keys - %w[todos]) } }

    assert_redirected_to household_url
    assert_equal %w[todos], @household.reload.excluded_planner_sections
    assert_not @household.plans_section?("todos")
  end

  test "the planner has to keep at least one step" do
    patch household_url, params: { household: { planner_sections: [ "" ] } }

    assert_response :unprocessable_entity
    assert_match "Keep at least one step in the weekly planner", response.body
    assert_empty @household.reload.excluded_planner_sections
  end

  test "limited members see the steps but can't change them" do
    leave_out("todos")
    sign_in users(:two) # bob, limited

    get household_url

    assert_select "input[name='household[planner_sections][]']", 0
    assert_match "Meals, Restock checklist, Grocery list, Chores, and Calendar", response.body
  end

  # ── The planner ──

  test "a left-out step isn't in the planner's steps" do
    leave_out("todos")

    get plan_week_step_url(section: "chores", week: @this_week)

    assert_select "nav[aria-label=Progress] a[href*='/todos']", 0
    assert_select "nav[aria-label=Progress] a[href*='/calendar']"
  end

  test "finishing the step before a left-out one moves straight past it" do
    leave_out("todos")

    patch plan_week_step_url(section: "chores", week: @this_week), params: { status: "done" }

    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)
  end

  test "the week counts as planned without the left-out steps" do
    leave_out("todos", "calendar")
    plan = WeeklyPlan.current_for(@household)
    (Dashboard.section_keys - %w[todos calendar]).each { |key| plan.section(key).mark!("done", by: users(:one)) }

    assert plan.reload.planned?
    assert_equal "meals", plan.active_key
  end

  test "resuming skips a left-out step" do
    leave_out("meals")

    get plan_week_url

    assert_redirected_to plan_week_step_url(section: "restock", week: @this_week)
  end

  test "a left-out step can still be opened directly, and moves on to the next planned one" do
    leave_out("todos")

    get plan_week_step_url(section: "todos", week: @this_week)
    assert_response :success

    patch plan_week_step_url(section: "todos", week: @this_week), params: { status: "done" }
    assert_redirected_to plan_week_step_url(section: "calendar", week: @this_week)
  end

  test "the print offer moves to the last planned step" do
    leave_out("calendar")

    get plan_week_step_url(section: "todos", week: @this_week)

    assert_select "a[href=?]", new_week_print_path(week: @this_week), text: /Print this week's plan/
  end

  # ── Printing ──

  test "a left-out step's page starts unticked on the print page" do
    leave_out("todos")

    get new_week_print_url(week: @this_week)

    assert_select "input[name='sections[]'][value=todos]:not([checked])"
    assert_select "input[name='sections[]'][value=chores][checked]"
  end

  test "leaving meals out also unticks the recipes page" do
    leave_out("meals")

    get new_week_print_url(week: @this_week)

    assert_select "input[name='sections[]'][value=meals]:not([checked])"
    assert_select "input[name='sections[]'][value=recipes]:not([checked])"
  end

  test "a left-out page can still be ticked and printed" do
    leave_out("todos")

    get new_week_print_url(week: @this_week, sections: %w[todos chores])

    assert_select "input[name='sections[]'][value=todos][checked]"
  end

  # ── The dashboard ──

  test "the dashboard still shows every area, and only names the planned steps" do
    leave_out("todos")

    get dashboard_url

    assert_match "Walk through meals, restocking, groceries, chores, and your calendar in a few minutes.", response.body
    assert_select "section[aria-labelledby=section-todos-heading]" # its card is still there
  end
end
