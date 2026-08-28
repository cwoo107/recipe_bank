class Chore < ApplicationRecord
  belongs_to :household
  belongs_to :assignee, class_name: "HouseholdMember", optional: true
  has_many :weekly_chores, dependent: :destroy

  FREQUENCIES = %w[weekly biweekly monthly quarterly semiannually annually].freeze

  # Only these two frequencies get a "remembered day" that auto-replicates
  # onto the board every week (or every other week) — see
  # WeeklyChore#sync_chore_default_weekday and .auto_schedule_recurring!
  # below. Anything less frequent than biweekly would otherwise camp on the
  # board indefinitely (a chore that's never marked done is always "due"),
  # so monthly+ chores are only ever surfaced via the Due soon list.
  RECURRING_FREQUENCIES = %w[weekly biweekly].freeze

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
  # assigned its current day.
  def biweekly_due_on_week?(week_start)
    return true if default_weekday_started_on.blank?
    ((week_start - default_weekday_started_on) / 7).to_i.even?
  end

  # Chores that are due but haven't already been added to this week's list —
  # the recommendations shown on the Chore Chart page and the planning wizard.
  # Recurring (weekly/biweekly) chores with a remembered day are excluded
  # entirely once assigned — they're fully handled by auto_schedule_recurring!
  # below and would otherwise show up here too on their "off" weeks.
  # Due-ness is checked as of the week being viewed (not "today"), so
  # navigating to a future week correctly reflects what's due by then.
  def self.due_and_unscheduled(household, week_start:)
    scheduled_ids = household.weekly_chores.where(week_start: week_start).pluck(:chore_id)
    household.chores.ordered.reject do |c|
      scheduled_ids.include?(c.id) || c.default_weekday.present? || !c.due?(as_of: week_start)
    end
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
      next unless chore.recurring?
      next if chore.frequency == "biweekly" && !chore.biweekly_due_on_week?(week_start)
      next if household.weekly_chores.exists?(chore_id: chore.id, week_start: week_start)

      scheduled_date = week_start + ((chore.default_weekday - week_start.wday) % 7)
      household.weekly_chores.create!(chore: chore, week_start: week_start, scheduled_date: scheduled_date)
    end
  end
end
