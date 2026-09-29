class WeeklyChore < ApplicationRecord
  belongs_to :household
  belongs_to :chore
  belongs_to :assignee, class_name: "HouseholdMember", optional: true

  # scheduled_date is normally always set (every chore lands on a day — see
  # first_available_day below); nil is still supported as a fallback
  # "unscheduled" state. Position is tracked per (week, day) the same way a
  # Todo's kanban column position is tracked per status.
  acts_as_list scope: [ :household_id, :week_start, :scheduled_date ]

  validates :week_start, presence: true
  validates :chore_id, uniqueness: { scope: :week_start }
  validate :scheduled_date_within_week

  # Set for a move that should only affect this one week (the board's "Just
  # this week" choice) — the chore keeps its remembered day, and other weeks
  # are left alone.
  attribute :this_week_only, :boolean, default: false

  before_validation :default_assignee_from_chore, on: :create
  after_save :sync_chore_default_weekday, if: -> { saved_change_to_scheduled_date? && !this_week_only }
  after_destroy :clear_chore_default_weekday, if: :scheduled?
  # Taking a finished instance off the board takes its completion with it.
  after_destroy :refresh_chore_last_completed!, if: :completed?

  # Skipped instances ("remove just this week" on a recurring chore) stay in
  # the table only so auto-scheduling knows not to recreate them — nothing
  # shows them.
  scope :not_skipped, -> { where(skipped: false) }
  scope :for_week, ->(week_start) { not_skipped.where(week_start: week_start).order(:position) }

  # The first day of the given week that doesn't already have a chore on it —
  # where a plain "Add to this week" click lands a chore, since every chore
  # now needs a day (there's no more unscheduled column to drop it in). Falls
  # back to the week's first day once every day already has something.
  def self.first_available_day(household, week_start)
    scheduled_dates = household.weekly_chores.not_skipped.where(week_start: week_start).where.not(scheduled_date: nil).pluck(:scheduled_date).to_set
    (0..6).map { |i| week_start + i }.find { |day| !scheduled_dates.include?(day) } || week_start
  end

  def scheduled?
    scheduled_date.present?
  end

  def mark_complete!
    update!(completed: true, completed_at: Time.current)
    refresh_chore_last_completed!
  end

  def mark_incomplete!
    update!(completed: false, completed_at: nil)
    refresh_chore_last_completed!
  end

  # Takes a recurring chore off just this one week, leaving its remembered
  # day (and every other week) alone. The row stays, marked skipped, so
  # Chore#schedule_into_week! won't put it straight back; the chore shows in
  # that week's Due soon row instead, and adding it again un-skips it.
  def skip!
    was_completed = completed?
    update!(skipped: true, completed: false, completed_at: nil)
    refresh_chore_last_completed! if was_completed
  end

  # Takes a recurring chore off this week and every later one: it forgets
  # its remembered day (see clear_chore_default_weekday) and its unfinished
  # later instances go too. Earlier weeks are left as they were.
  def remove_going_forward!
    transaction do
      chore.weekly_chores.where(completed: false).where("week_start > ?", week_start).delete_all
      destroy!
    end
  end

  # Re-stamps an already-completed instance as done just now.
  def touch_completion!
    update!(completed_at: Time.current)
    refresh_chore_last_completed!
  end

  # Drag-and-drop move between days. Mirrors Todo#move_to_column!. By
  # default the new day applies going forward (see sync_chore_default_weekday);
  # this_week_only: true moves just this instance.
  def move_to_day!(new_date, new_position = nil, this_week_only: false)
    return if new_date == scheduled_date && (new_position.nil? || new_position == position)

    self.this_week_only = this_week_only
    old_date = scheduled_date
    self.scheduled_date = new_date
    remove_from_list if old_date != new_date

    if new_position
      insert_at(new_position.to_i)
    else
      move_to_bottom
    end

    save!
  end

  private

  def default_assignee_from_chore
    self.assignee_id ||= chore&.assignee_id
  end

  def scheduled_date_within_week
    return if scheduled_date.blank? || week_start.blank?

    unless (week_start...(week_start + 7)).cover?(scheduled_date)
      errors.add(:scheduled_date, "must fall within this chore's week")
    end
  end

  # Recomputed from the completion history rather than just taking "now", so
  # unchecking a chore correctly falls back to its previous completion (if any).
  def refresh_chore_last_completed!
    chore.update!(last_completed_at: chore.weekly_chores.where(completed: true).maximum(:completed_at))
  end

  # Scheduling (or unscheduling) onto a day updates the chore's remembered
  # weekday, so Chore.auto_schedule_recurring! can replicate it onto that
  # same day next time it's due — no manual re-drag needed. The change only
  # ever applies from this instance's week forward (Chore#reschedule_forward!):
  # already-generated later weeks move with it, earlier weeks never do.
  #
  # Only weekly/biweekly chores get this treatment (Chore::RECURRING_FREQUENCIES)
  # — a monthly+ chore that's never marked done is always "due", so without
  # this gate it would camp on the same day every single week regardless of
  # its real frequency. Those chores are scheduled for one week at a time
  # only, and go back to surfacing via the Due soon list once due again.
  def sync_chore_default_weekday
    return unless chore.recurring?

    chore.reschedule_forward!(scheduled_date&.wday, from_week: week_start)
    return if scheduled_date.present?

    chore.weekly_chores.where.not(id: id).where("week_start > ?", week_start)
         .where(completed: false).where.not(scheduled_date: nil)
         .update_all(scheduled_date: nil)
  end

  def clear_chore_default_weekday
    chore.update!(default_weekday: nil, default_weekday_started_on: nil)
  end
end
