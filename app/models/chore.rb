class Chore < ApplicationRecord
  belongs_to :household
  belongs_to :assignee, class_name: "HouseholdMember", optional: true
  # Optional so deleting a category (which nullifies) doesn't orphan-validate
  # its chores — they land in the board's "Uncategorized" row instead.
  belongs_to :chore_category, optional: true
  has_many :weekly_chores, dependent: :destroy
  has_many :chore_tasks, -> { order(:position) }, dependent: :destroy, inverse_of: :chore

  FREQUENCIES = %w[weekly biweekly monthly quarterly semiannually annually].freeze

  # Only these two frequencies get a "remembered day" that auto-replicates
  # onto the board every week (or every other week) — see
  # WeeklyChore#sync_chore_default_weekday and .auto_schedule_recurring!
  # below. Anything less frequent than biweekly would otherwise camp on the
  # board indefinitely (a chore that's never marked done is always "due"),
  # so monthly+ chores are only ever surfaced via the Due soon list.
  RECURRING_FREQUENCIES = %w[weekly biweekly].freeze

  # How far ahead of the viewed week the board's "Due soon" row looks for
  # chores that are coming due but aren't on the board yet.
  DUE_SOON_HORIZON = 1.month

  FREQUENCY_INTERVALS = {
    "weekly"       => 1.week,
    "biweekly"     => 2.weeks,
    "monthly"      => 1.month,
    "quarterly"    => 3.months,
    "semiannually" => 6.months,
    "annually"     => 1.year
  }.freeze

  FREQUENCY_LABELS = {
    "weekly"       => "Weekly",
    "biweekly"     => "Every 2 weeks",
    "monthly"      => "Monthly",
    "quarterly"    => "Quarterly",
    "semiannually" => "Every 6 months",
    "annually"     => "Annually"
  }.freeze

  # Short enough to fit a pill on a compact board card.
  FREQUENCY_SHORT_LABELS = {
    "weekly"       => "Weekly",
    "biweekly"     => "2 wks",
    "monthly"      => "Monthly",
    "quarterly"    => "Qtrly",
    "semiannually" => "6 mos",
    "annually"     => "Annual"
  }.freeze

  # Reuses the app's existing palette (see dashboard/_icon.html.erb, Todo
  # priority colors) so a frequency pill reads consistently with the rest
  # of the UI rather than introducing new colors.
  FREQUENCY_PILL_CLASSES = {
    "weekly"       => "bg-seafoam-100 text-seafoam-800 dark:bg-seafoam-900/30 dark:text-seafoam-300",
    "biweekly"     => "bg-mist-100 text-mist-800 dark:bg-mist-900/30 dark:text-mist-300",
    "monthly"      => "bg-honey-100 text-honey-800 dark:bg-honey-900/30 dark:text-honey-300",
    "quarterly"    => "bg-mauve-100 text-mauve-800 dark:bg-mauve-900/30 dark:text-mauve-300",
    "semiannually" => "bg-terracotta-100 text-terracotta-800 dark:bg-terracotta-900/30 dark:text-terracotta-300",
    "annually"     => "bg-dusty-rose-100 text-dusty-rose-800 dark:bg-dusty-rose-900/30 dark:text-dusty-rose-300"
  }.freeze

  validates :name, presence: true
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :default_weekday, inclusion: { in: 0..6 }, allow_nil: true
  validate :chore_category_in_same_household

  # A remembered day only means anything for weekly/biweekly chores (see
  # RECURRING_FREQUENCIES above), so switching to a less frequent one drops it.
  before_save :forget_default_weekday, if: -> { will_save_change_to_frequency? && !recurring? }
  after_update :reassign_upcoming_weekly_chores, if: :saved_change_to_assignee_id?

  scope :ordered, -> { order(:name) }

  # Never completed -> due right away. Otherwise, due when the frequency's
  # interval has elapsed since the last completion.
  def next_due_on
    return Date.current if last_completed_at.blank?
    last_completed_at.to_date + FREQUENCY_INTERVALS.fetch(frequency)
  end

  def due?(as_of: Date.current)
    return true if last_completed_at.blank? # never done -> always due, regardless of as_of
    next_due_on <= as_of
  end

  # When this chore next needs doing, for display on Manage Chores. A
  # recurring chore with a remembered day follows its schedule — the first
  # unfinished instance from this week on (which may already be overdue) —
  # rather than the completion-based next_due_on.
  def next_due_date(today: Date.current)
    return next_due_on unless recurring? && default_weekday.present?

    week     = today.beginning_of_week
    horizon  = week + 6.weeks
    existing = weekly_chores.where(week_start: week...horizon).index_by(&:week_start)

    while week < horizon
      if (instance = existing[week])
        return instance.scheduled_date if !instance.completed? && !instance.skipped? && instance.scheduled_date
      elsif scheduled_on_week?(week)
        return default_weekday_in(week)
      end
      week += 7
    end

    next_due_on
  end

  def frequency_label
    FREQUENCY_LABELS.fetch(frequency)
  end

  def frequency_short_label
    FREQUENCY_SHORT_LABELS.fetch(frequency)
  end

  def frequency_pill_classes
    FREQUENCY_PILL_CLASSES.fetch(frequency)
  end

  def recurring?
    RECURRING_FREQUENCIES.include?(frequency)
  end

  # For a biweekly chore, is `week_start` an "on" week (vs. the alternating
  # "off" week it should skip)? Counts in 2-week steps from
  # default_weekday_started_on, the week the chore was (most recently)
  # assigned its current day. Compares the chore's actual day in each week
  # rather than the week starts themselves, so the rhythm survives the
  # household changing which day its weeks start on.
  def biweekly_due_on_week?(week_start)
    return true if default_weekday_started_on.blank?
    ((default_weekday_in(week_start) - default_weekday_in(default_weekday_started_on)) / 7).to_i.even?
  end

  # The date this chore's remembered weekday falls on in the week starting
  # `week_start` (the week start itself when there's no remembered day).
  def default_weekday_in(week_start)
    return week_start if default_weekday.blank?
    week_start + ((default_weekday - week_start.wday) % 7)
  end

  # Would auto-scheduling put this chore on the week starting `week_start`?
  # A remembered day only applies from the week it was set onward
  # (default_weekday_started_on) — rescheduling is forward-only, so earlier
  # weeks never pick up a day that was chosen after them. Compared by the
  # actual day the chore would land on, so it holds up across a change to
  # the household's week start day.
  def scheduled_on_week?(week_start)
    return false unless recurring? && default_weekday.present?
    return false if default_weekday_started_on.present? && default_weekday_in(week_start) < default_weekday_started_on
    return false if frequency == "biweekly" && !biweekly_due_on_week?(week_start)
    true
  end

  # Puts this chore on the given week on its remembered day, unless it's not
  # scheduled for that week or is already there.
  def schedule_into_week!(week_start)
    return unless scheduled_on_week?(week_start)
    return if weekly_chores.exists?(week_start: week_start)

    household.weekly_chores.create!(chore: self, week_start: week_start, scheduled_date: default_weekday_in(week_start))
  end

  # Changes the remembered day from `from_week` onward — the week the change
  # was made in, never earlier. Unfinished instances already on the board for
  # that week and later move to the new day; earlier weeks keep whatever day
  # they had. When `from_week` is in the future, the weeks between now and
  # then are filled in on the old day first, since the new day won't apply
  # to them.
  def reschedule_forward!(weekday, from_week:)
    return if weekday == default_weekday
    return unless recurring?

    if weekday.nil?
      update!(default_weekday: nil, default_weekday_started_on: nil)
      return
    end

    fill_weeks_before!(from_week)
    update!(default_weekday: weekday, default_weekday_started_on: from_week)

    weekly_chores.where(completed: false).where(week_start: from_week..).find_each do |instance|
      new_date = instance.week_start + ((weekday - instance.week_start.wday) % 7)
      instance.update_column(:scheduled_date, new_date) unless instance.scheduled_date == new_date
    end
  end

  # Chores coming due within DUE_SOON_HORIZON of the viewed week that
  # haven't already been added to it — the board's "Due soon" row, and the
  # planning wizard's. Recurring (weekly/biweekly) chores with a remembered
  # day are excluded entirely once assigned — they're fully handled by
  # auto_schedule_recurring! below and would otherwise show up here too on
  # their "off" weeks (unless skipped for that week, which puts them back
  # here). Due-ness is checked relative to the week being viewed
  # (not "today"), so navigating to a future week reflects what's due by then.
  def self.due_soon(household, week_start:)
    instances   = household.weekly_chores.where(week_start: week_start)
    on_board    = instances.not_skipped.pluck(:chore_id).to_set
    skipped_ids = instances.where(skipped: true).pluck(:chore_id).to_set
    household.chores.ordered.includes(:assignee).select do |c|
      next false if on_board.include?(c.id)
      # Taken off just this week — offer it back for this week.
      skipped_ids.include?(c.id) || c.due_soon?(week_start: week_start)
    end
  end

  # Belongs in the week's Due soon row (when it isn't already on the board).
  def due_soon?(week_start:)
    default_weekday.blank? && due?(as_of: week_start + DUE_SOON_HORIZON)
  end

  # Once a weekly/biweekly chore has been dragged onto a day, it "remembers"
  # that weekday (default_weekday) and replicates onto it automatically —
  # every week for weekly, every other week for biweekly — regardless of
  # completion status (that's what "recurring" means). Monthly+ chores never
  # get a default_weekday in the first place (see
  # WeeklyChore#sync_chore_default_weekday), so they never reach here; they
  # only ever resurface via the Due soon list above.
  def self.auto_schedule_recurring!(household, week_start:)
    household.chores.where.not(default_weekday: nil).find_each do |chore|
      chore.schedule_into_week!(week_start)
    end
  end

  private

  # Materializes this week through the week before `week` on the current
  # remembered day (capped, in case `week` is far in the future).
  def fill_weeks_before!(week)
    return if default_weekday.blank?

    current = Date.current.beginning_of_week
    52.times do
      break if current >= week
      schedule_into_week!(current)
      current += 7
    end
  end

  def forget_default_weekday
    self.default_weekday = nil
    self.default_weekday_started_on = nil
  end

  def chore_category_in_same_household
    return if chore_category.nil? || chore_category.household_id == household_id
    errors.add(:chore_category, "must belong to this household")
  end

  # Reassigning a chore carries over to this week's and future unfinished
  # instances already on the board; finished ones keep who actually did them.
  def reassign_upcoming_weekly_chores
    weekly_chores.where(completed: false)
                 .where(week_start: Date.current.beginning_of_week..)
                 .update_all(assignee_id: assignee_id)
  end
end
