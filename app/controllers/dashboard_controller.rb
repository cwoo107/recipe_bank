class DashboardController < ApplicationController
  # How each planner step reads in "Walk through meals, restocking, … in a
  # few minutes."
  PLANNING_PHRASES = {
    "meals" => "meals", "restock" => "restocking", "groceries" => "groceries",
    "chores" => "chores", "todos" => "to-dos", "calendar" => "your calendar"
  }.freeze

  def show
    # Any week, stepped through with Previous/Next like the meal planner
    # (?date=); this week by default.
    @week_start  = week_start_from_params
    @this_week   = @week_start == Date.current.beginning_of_week
    # "this week" / "next week" / "the week of Oct 26", for the page's copy.
    @week_phrase = Dashboard::Section.week_phrase_for(@week_start)
    # Only weeks the planner can plan get its buttons — any other week would
    # just send you to a different one.
    @plannable   = WeeklyPlan.plannable_week?(@week_start)
    @weekly_plan = WeeklyPlan.current_for(current_household, week_start: @week_start)
    # Landing on the dashboard ends any planning session, whichever week.
    current_household.weekly_plans.where(currently_planning: true).update_all(currently_planning: false)
    @weekly_plan.reload
    @next_week_to_plan = WeeklyPlan.week_to_plan(current_household)
    @unfinished_plan   = household_admin? ? WeeklyPlan.unfinished_for(current_household) : nil # planning is admin-only
    # Every area gets its card — leaving one out of the planner doesn't hide
    # it here — but only the planned ones decide whether the week reads as
    # "nothing planned" or "fully planned".
    @sections    = Dashboard.sections.map do |klass|
      klass.new(household: current_household, week_start: @week_start, weekly_plan: @weekly_plan)
    end
    # (In the planner's order, for "Walk through …".)
    planned_sections = @sections.select { |section| current_household.plans_section?(section.key) }
                                .sort_by { |section| Dashboard.planner_section_keys.index(section.key) }

    @nothing_planned = planned_sections.all?(&:empty?)
    @everything_done = planned_sections.none?(&:empty?)
    @planned_steps   = planned_sections.map { |section| PLANNING_PHRASES.fetch(section.key, section.label.downcase) }
  end

  private

  def week_start_from_params
    (Date.iso8601(params[:date].to_s) rescue Date.current).beginning_of_week
  end
end
