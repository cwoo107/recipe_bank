class WeeklyPlan < ApplicationRecord
  belongs_to :household
  has_many :weekly_plan_sections, dependent: :destroy

  validates :week_start, presence: true, uniqueness: { scope: :household_id }

  # How far ahead the wizard lets you plan — enough for "next week" and a
  # little beyond, without piling up rows for weeks nobody will reach.
  WEEKS_AHEAD = 4

  def self.current_for(household, week_start: Date.current.beginning_of_week)
    find_or_create_by!(household: household, week_start: week_start)
  end

  # The plan the household is partway through right now, if any. Past weeks
  # don't count — a stale session from last week shouldn't resurface.
  def self.in_progress_for(household)
    where(household: household, currently_planning: true)
      .where(week_start: Date.current.beginning_of_week..)
      .order(updated_at: :desc)
      .first
  end

  # A session that was started and then left (the bar closed, or the user
  # wandered off) before the wizard was finished — what the dashboard offers
  # to continue.
  def self.unfinished_for(household)
    where(household: household, currently_planning: false)
      .where(week_start: Date.current.beginning_of_week..)
      .where.not(planning_started_at: nil)
      .where("planning_completed_at IS NULL OR planning_completed_at < planning_started_at")
      .order(updated_at: :desc)
      .first
  end

  # Which week "Plan your week" should open: whatever's already in progress,
  # otherwise this week — or next week once this one is planned.
  def self.week_to_plan(household)
    in_progress = in_progress_for(household)
    return in_progress.week_start if in_progress

    this_week = Date.current.beginning_of_week
    find_by(household: household, week_start: this_week)&.planned? ? this_week + 7 : this_week
  end

  # The weeks the wizard can switch between: this week through WEEKS_AHEAD.
  def self.plannable_weeks
    this_week = Date.current.beginning_of_week
    (0..WEEKS_AHEAD).map { |n| this_week + (7 * n) }
  end

  def self.plannable_week?(date)
    plannable_weeks.include?(date)
  end

  # "This week", "Next week", or the date range for anything further out.
  def self.week_label(week_start)
    case (week_start - Date.current.beginning_of_week).to_i / 7
    when 0 then "This week"
    when 1 then "Next week"
    else "Week of #{week_start.strftime('%b %-d')}"
    end
  end

  def self.week_range_label(week_start)
    week_end = week_start + 6
    format = week_start.month == week_end.month ? "%-d" : "%b %-d"
    "#{week_start.strftime('%b %-d')} – #{week_end.strftime(format)}"
  end

  # Finished the wizard, or walked every step some other way. Steps the
  # household has left out of the planner (Household#planner_section_keys)
  # don't count.
  def planned?
    planning_completed_at.present? || planner_keys.none? { |k| incomplete?(k) }
  end

  # The steps this household plans, in order.
  def planner_keys = household.planner_section_keys

  def week_label       = self.class.week_label(week_start)
  def week_range_label = self.class.week_range_label(week_start)

  def section(key)
    weekly_plan_sections.find_or_create_by!(key: key.to_s)
  end

  # Read-only status lookups (unlike #section, never create a row) — cheap
  # enough to call on every page load for the sticky "continue planning" bar.
  def statuses
    @statuses ||= weekly_plan_sections.pluck(:key, :status).to_h
  end

  def reload(...)
    @statuses = nil
    super
  end

  def section_status(key)
    statuses.fetch(key.to_s, "not_started")
  end

  def incomplete?(key)
    !%w[done skipped].include?(section_status(key))
  end

  # The step "in progress" right now — where the wizard resumes, and what
  # the sticky planning bar acts on from anywhere else in the app.
  def active_key
    planner_keys.find { |k| incomplete?(k) } || planner_keys.first
  end

  # The next unfinished planner step after `key`. Placed by the full
  # Dashboard order, so this also works from a step left out of the planner
  # that was opened directly (a dashboard card's button): it moves on to the
  # next included one.
  def next_key_after(key)
    keys = Dashboard.section_keys
    idx = keys.index(key.to_s)
    return nil unless idx

    keys[(idx + 1)..].find { |k| household.plans_section?(k) && incomplete?(k) }
  end

  # The planner step before `key`, the same way.
  def previous_key_before(key)
    keys = Dashboard.section_keys
    idx = keys.index(key.to_s)
    return nil unless idx

    keys[0...idx].reverse.find { |k| household.plans_section?(k) }
  end
end
