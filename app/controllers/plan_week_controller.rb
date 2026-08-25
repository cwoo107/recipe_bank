class PlanWeekController < ApplicationController
  before_action :set_week_context
  before_action :set_section, only: [ :show, :update ]

  # Resumable by construction: the resume point is recomputed from stored
  # section statuses every time, so closing the tab mid-flow and coming back
  # just lands here again and picks up where they left off.
  def start
    redirect_to plan_week_step_path(section: @weekly_plan.active_key)
  end

  # Also the standalone entry point for a single step — a dashboard card's
  # button, or the sticky planning bar, links straight here without going
  # through #start.
  def show
    @sections = sections
    current_index = Dashboard.sections.index(Dashboard.section_class(params[:section]))
    @previous_key = current_index.positive? ? Dashboard.sections[current_index - 1]::KEY : nil
  end

  def update
    status = params[:status]
    return head :bad_request unless WeeklyPlanSection::STATUSES.include?(status)

    @dashboard_section.weekly_plan_section.mark!(status, by: current_user)

    next_key = @weekly_plan.next_key_after(params[:section])
    if next_key
      redirect_to plan_week_step_path(section: next_key)
    else
      @weekly_plan.update!(currently_planning: false)
      redirect_to dashboard_path, notice: "Weekly plan updated."
    end
  end

  private

  def set_week_context
    @week_start  = Date.current.beginning_of_week
    @weekly_plan = WeeklyPlan.current_for(current_household, week_start: @week_start)
    @weekly_plan.update!(currently_planning: true) unless @weekly_plan.currently_planning?
  end

  def sections
    @sections ||= Dashboard.sections.map do |klass|
      klass.new(household: current_household, week_start: @week_start, weekly_plan: @weekly_plan)
    end
  end

  def set_section
    klass = Dashboard.section_class(params[:section])
    return redirect_to plan_week_path unless klass

    @dashboard_section = klass.new(household: current_household, week_start: @week_start, weekly_plan: @weekly_plan)
  end
end
