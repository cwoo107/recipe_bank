class WeeklyPlan < ApplicationRecord
  belongs_to :household
  has_many :weekly_plan_sections, dependent: :destroy

  validates :week_start, presence: true, uniqueness: { scope: :household_id }

  def self.current_for(household, week_start: Date.current.beginning_of_week)
    find_or_create_by!(household: household, week_start: week_start)
  end

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
    Dashboard.section_keys.find { |k| incomplete?(k) } || Dashboard.section_keys.first
  end

  def next_key_after(key)
    keys = Dashboard.section_keys
    idx = keys.index(key.to_s)
    return nil unless idx

    keys[(idx + 1)..].find { |k| incomplete?(k) }
  end
end
