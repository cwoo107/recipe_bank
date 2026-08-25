require "test_helper"

class WeeklyPlanTest < ActiveSupport::TestCase
  test "current_for finds or creates a plan for the given household and week" do
    household = households(:one)
    week_start = Date.current.beginning_of_week

    assert_difference("WeeklyPlan.count", 1) do
      WeeklyPlan.current_for(household, week_start: week_start)
    end

    assert_no_difference("WeeklyPlan.count") do
      again = WeeklyPlan.current_for(household, week_start: week_start)
      assert_equal week_start, again.week_start
    end
  end

  test "two households can each have their own plan for the same week" do
    week_start = Date.current.beginning_of_week
    plan_one = WeeklyPlan.current_for(households(:one), week_start: week_start)
    plan_two = WeeklyPlan.current_for(households(:two), week_start: week_start)

    refute_equal plan_one, plan_two
  end

  test "section finds or creates a section by key" do
    plan = WeeklyPlan.current_for(households(:one))

    assert_difference("WeeklyPlanSection.count", 1) do
      section = plan.section("meals")
      assert_equal "not_started", section.status
    end

    assert_no_difference("WeeklyPlanSection.count") do
      plan.section("meals")
    end
  end

  test "active_key is the first section that isn't done or skipped" do
    plan = WeeklyPlan.current_for(households(:one))
    assert_equal "meals", plan.active_key

    plan.section("meals").mark!("done", by: users(:one))
    assert_equal "groceries", plan.reload.active_key
  end

  test "active_key falls back to the first section once everything is done or skipped" do
    plan = WeeklyPlan.current_for(households(:one))
    %w[meals todos groceries calendar].each { |k| plan.section(k).mark!("done", by: users(:one)) }

    assert_equal "meals", plan.reload.active_key
  end

  test "next_key_after finds the next incomplete section, skipping ones already done or skipped" do
    plan = WeeklyPlan.current_for(households(:one))
    plan.section("groceries").mark!("skipped", by: users(:one))

    assert_equal "todos", plan.reload.next_key_after("meals")
  end

  test "next_key_after returns nil after the last section" do
    plan = WeeklyPlan.current_for(households(:one))
    assert_nil plan.next_key_after("calendar")
  end

  test "section_status defaults to not_started for a section never touched" do
    plan = WeeklyPlan.current_for(households(:one))
    assert_equal "not_started", plan.section_status("meals")
  end
end
