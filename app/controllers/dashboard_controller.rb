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

    # Once this week has been planned, desktop gets a bento grid of what's on
    # now (dashboard/_bento) in place of the cards. "Today" means nothing
    # for another week, so other weeks — and phones — keep the cards.
    @bento = @this_week && !@nothing_planned
    load_bento if @bento
  end

  private

  def load_bento
    today = Date.current
    section = ->(klass) { @sections.find { |s| s.key == klass::KEY } }
    @calendar_section = section.(Dashboard::CalendarSection)
    @todays_chores    = section.(Dashboard::ChoresSection).chores_this_week.select { |chore| chore.scheduled_date == today }
    # In the order "Plan your week" set for working through them.
    @up_next_todos    = Todo.up_next(current_household)
    # { "breakfast" => [...], "lunch" => [...], "dinner" => [...] }.
    @todays_meals     = section.(Dashboard::MealsSection).meals_this_week.select { |meal| meal.date == today }
                               .group_by { |meal| meal.meal_name.downcase }
  end

  def week_start_from_params
    (Date.iso8601(params[:date].to_s) rescue Date.current).beginning_of_week
  end
end
