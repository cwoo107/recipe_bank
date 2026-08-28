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

  before_validation :default_assignee_from_chore, on: :create
  after_save :sync_chore_default_weekday, if: :saved_change_to_scheduled_date?
  after_destroy :clear_chore_default_weekday, if: :scheduled?

  scope :for_week, ->(week_start) { where(week_start: week_start).order(:position) }

  # The first day (Mon..Sun) of the given week that doesn't already have a
  # chore on it — where a plain "Add to this week" click lands a chore, since
  # every chore now needs a day (there's no more unscheduled column to drop
  # it in). Falls back to Monday once every day already has something.
  def self.first_available_day(household, week_start)
    scheduled_dates = household.weekly_chores.where(week_start: week_start).where.not(scheduled_date: nil).pluck(:scheduled_date).to_set
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

  # Drag-and-drop move between days. Mirrors Todo#move_to_column!.
  def move_to_day!(new_date, new_position = nil)
    return if new_date == scheduled_date && (new_position.nil? || new_position == position)

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
  # same day next time it's due — no manual re-drag needed. Also propagates
  # the change to any future weeks that already auto-scheduled themselves
  # before this move happened, so rescheduling this week's instance doesn't
  # leave already-generated future weeks stuck on the old day.
  #
  # Only weekly/biweekly chores get this treatment (Chore::RECURRING_FREQUENCIES)
  # — a monthly+ chore that's never marked done is always "due", so without
  # this gate it would camp on the same day every single week regardless of
  # its real frequency. Those chores are scheduled for one week at a time
  # only, and go back to surfacing via the Due soon list once due again.
  def sync_chore_default_weekday
    return unless chore.recurring?

    new_weekday = scheduled_date&.wday
    started_on = new_weekday.present? ? (new_weekday == chore.default_weekday ? chore.default_weekday_started_on : week_start) : nil
    chore.update!(default_weekday: new_weekday, default_weekday_started_on: started_on)
    propagate_to_future_instances
  end

  def propagate_to_future_instances
    future = chore.weekly_chores.where.not(id: id).where("week_start > ?", week_start).where(completed: false)

    if scheduled_date.present?
      new_wday = scheduled_date.wday
      future.find_each do |future_chore|
        new_date = future_chore.week_start + ((new_wday - future_chore.week_start.wday) % 7)
        future_chore.update_column(:scheduled_date, new_date) unless future_chore.scheduled_date == new_date
      end
    else
      future.where.not(scheduled_date: nil).update_all(scheduled_date: nil)
    end
  end

  def clear_chore_default_weekday
    chore.update!(default_weekday: nil, default_weekday_started_on: nil)
  end
end
