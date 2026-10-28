class PlanWeekController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
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
    @previous_key = @weekly_plan.previous_key_before(@dashboard_section.key)
  end

  def update
    status = params[:status]
    return head :bad_request unless WeeklyPlanSection::STATUSES.include?(status)

    @dashboard_section.weekly_plan_section.mark!(status, by: current_user)
    @weekly_plan.reload # drops the cached statuses

    # Onward first, then back round to any earlier step still open — a step
    # opened straight from a dashboard card shouldn't finish the week.
    next_key = @weekly_plan.next_key_after(params[:section]) || @weekly_plan.first_incomplete_key
    if next_key
      redirect_to plan_week_step_path(section: next_key, week: @week_start)
    else
      notice = completion_notice # before the stamp — it asks whether this is a first finish
      @weekly_plan.update!(currently_planning: false, planning_completed_at: Time.current)
      redirect_to dashboard_path, notice: notice
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
    @weekly_plan.start_planning_session! unless @weekly_plan.currently_planning?
  end

  def requested_week
    date = Date.iso8601(params[:week].to_s).beginning_of_week
    date if WeeklyPlan.plannable_week?(date)
  rescue Date::Error
    nil
  end

  # The time is the week's total across every session (see
  # WeeklyPlan#track_planning_time!). Finishing a reopened plan again isn't
  # a new plan, so it gets no time.
  def completion_notice
    week = @weekly_plan.week_label.downcase
    return "Plan for #{week} updated." if @weekly_plan.planning_completed_at

    minutes = (@weekly_plan.planning_seconds / 60.0).round
    took = minutes.zero? ? "less than a minute" : "#{minutes} #{minutes == 1 ? 'minute' : 'minutes'}"
    "Congrats! It just took you #{took} to plan #{week}."
  end

  # The planner's steps — only the ones this household plans (see
  # Household#planner_section_keys). A left-out step can still be opened
  # directly (set_section doesn't filter); it just isn't in the progress bar.
  def sections
    @sections ||= Dashboard.planner_sections.select { |klass| current_household.plans_section?(klass::KEY) }.map do |klass|
      klass.new(household: current_household, week_start: @week_start, weekly_plan: @weekly_plan)
    end
  end

  def set_section
    klass = Dashboard.section_class(params[:section])
    return redirect_to plan_week_path unless klass

    @dashboard_section = klass.new(household: current_household, week_start: @week_start, weekly_plan: @weekly_plan)
  end
end
