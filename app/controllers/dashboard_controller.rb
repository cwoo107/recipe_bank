class DashboardController < ApplicationController
  def show
    @week_start  = Date.current.beginning_of_week
    @weekly_plan = WeeklyPlan.current_for(current_household, week_start: @week_start)
    @weekly_plan.update!(currently_planning: false) if @weekly_plan.currently_planning?
    @sections    = Dashboard.sections.map do |klass|
      klass.new(household: current_household, week_start: @week_start, weekly_plan: @weekly_plan)
    end

    @nothing_planned = @sections.all?(&:empty?)
    @everything_done = @sections.none?(&:empty?)
  end
end
