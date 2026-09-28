class PlanWeekController < ApplicationController
  before_action :set_week_context, except: :close
  before_action :set_section, only: [ :show, :update ]

  # Resumable by construction: the resume point is recomputed from stored
  # section statuses every time, so closing the tab mid-flow and coming back
  # just lands here again and picks up where they left off.
  def start
    redirect_to plan_week_step_path(section: @weekly_plan.active_key, week: @week_start)
  end

  # Also the standalone entry point for a single step — a dashboard card's
  # button, or the sticky planning bar, links straight here without going
  # through #start.
  def show
    @sections = sections
    @week_plans = current_household.weekly_plans.where(week_start: @plannable_weeks).index_by(&:week_start)
    current_index = Dashboard.sections.index(Dashboard.section_class(params[:section]))
    @previous_key = current_index.positive? ? Dashboard.sections[current_index - 1]::KEY : nil
  end

  def update
    status = params[:status]
    return head :bad_request unless WeeklyPlanSection::STATUSES.include?(status)

    @dashboard_section.weekly_plan_section.mark!(status, by: current_user)

    next_key = @weekly_plan.next_key_after(params[:section])
    if next_key
      redirect_to plan_week_step_path(section: next_key, week: @week_start)
    else
      @weekly_plan.update!(currently_planning: false, planning_completed_at: Time.current)
      redirect_to dashboard_path, notice: completion_notice
    end
  end

  # Closes the sticky planning bar by ending the session. Step statuses are
  # kept, so "Continue planning" on the dashboard picks up where they left off.
  def close
    current_household.weekly_plans.where(currently_planning: true).update_all(currently_planning: false)
    redirect_back_or_to dashboard_path, status: :see_other
  end

  private

  # The week comes from ?week= when the user has picked one; otherwise it's
  # whichever week needs planning (see WeeklyPlan.week_to_plan). Only one
  # week is "currently planning" at a time, so switching weeks hands the
  # sticky bar over to the new one.
  def set_week_context
    @week_start  = requested_week || WeeklyPlan.week_to_plan(current_household)
    @weekly_plan = WeeklyPlan.current_for(current_household, week_start: @week_start)
    @plannable_weeks = WeeklyPlan.plannable_weeks

    current_household.weekly_plans.where(currently_planning: true)
                     .where.not(id: @weekly_plan.id).update_all(currently_planning: false)
    unless @weekly_plan.currently_planning?
      @weekly_plan.update!(currently_planning: true, planning_started_at: Time.current)
    end
  end

  def requested_week
    date = Date.iso8601(params[:week].to_s).beginning_of_week
    date if WeeklyPlan.plannable_week?(date)
  rescue Date::Error
    nil
  end

  def completion_notice
    week = @weekly_plan.week_label.downcase
    return "Plan for #{week} updated." unless @weekly_plan.planning_started_at

    minutes = ((Time.current - @weekly_plan.planning_started_at) / 60.0).round
    unit = minutes == 1 ? "minute" : "minutes"
    "Congrats! It just took you #{minutes} #{unit} to plan #{week}."
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
