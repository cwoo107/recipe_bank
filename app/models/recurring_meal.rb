class RecurringMeal < ApplicationRecord
  belongs_to :household
  belongs_to :user
  belongs_to :recipe

  has_many :recurring_meal_occurrences, dependent: :destroy
  has_many :meals, dependent: :nullify
  has_many :recurring_meal_assignments, dependent: :destroy
  has_many :eaters, through: :recurring_meal_assignments, source: :household_member

  serialize :days_of_week, type: Array, coder: JSON

  PATTERN_TYPES = %w[interval days_of_week].freeze
  # Recurring only makes sense for date-scheduled meals, not the week-level
  # snack/dessert entries.
  MEAL_NAMES = Meal::CALENDAR_TYPES.freeze

  # Virtual attribute the form submits instead of a raw end_date: "week"
  # (end of the start date's week), "ongoing" (no end_date), or "date" (use
  # the submitted end_date as-is). Resolved into end_date before validation
  # so callers never have to compute it themselves.
  attr_accessor :end_type

  before_validation :apply_end_type
  before_validation :normalize_days_of_week

  validates :meal_name, inclusion: { in: MEAL_NAMES.map(&:capitalize) + MEAL_NAMES }
  validates :pattern_type, inclusion: { in: PATTERN_TYPES }
  validates :start_date, presence: true
  validates :interval_days, numericality: { only_integer: true, greater_than: 0 }, if: -> { pattern_type == "interval" }
  validate :days_of_week_present, if: -> { pattern_type == "days_of_week" }
  validate :end_date_not_before_start_date

  def self.materialize_household_week!(household, week_start)
    household.recurring_meals.find_each { |rule| rule.materialize_week!(week_start) }
  end

  def occurs_on?(date)
    return false if date < start_date
    return false if end_date && date > end_date

    case pattern_type
    when "interval"      then ((date - start_date).to_i % interval_days).zero?
    when "days_of_week"  then days_of_week.include?(date.wday)
    else false
    end
  end

  # Idempotent: creates a Meal + occurrence tombstone for each date this week
  # the rule covers that hasn't already been generated. Returns the newly
  # created Meals (empty if the week was already fully materialized).
  def materialize_week!(week_start)
    created = []

    (week_start...(week_start + 7)).each do |date|
      next unless occurs_on?(date)
      next if recurring_meal_occurrences.exists?(date: date)

      meal = household.meals.create!(
        user: user,
        recipe: recipe,
        meal_name: meal_name,
        servings: servings || recipe.servings || household.family_size,
        date: date,
        recurring_meal: self,
        eater_ids: eater_ids
      )
      recurring_meal_occurrences.create!(date: date, meal: meal)
      created << meal
    end

    created
  end

  # "Move this and all later ones" from the meals board drag and drop (see
  # MealsController#move). The dragged meal goes to to_date / to_meal_name,
  # and the rule follows from the dragged meal's date on:
  #   - the whole sequence takes the new meal type;
  #   - a days-of-week rule swaps the dragged weekday for the new one
  #     (Mon/Wed/Fri, Wed dragged to Thu → Mon/Thu/Fri);
  #   - an every-N-days rule shifts its cycle by the same number of days.
  # Like editing the rule, earlier meals it already created are left alone.
  # Later ones it created (and the occurrence tombstones, so a meal someone
  # removed stays removed) shift along with it. Where a shifted occurrence
  # lands on a date the rule already covers, the duplicate is dropped —
  # except the dragged meal itself, which stays where it was put.
  def move_sequence!(meal, to_date:, to_meal_name:)
    from   = meal.date
    offset = (to_date - from).to_i
    # A whole number of cycles (a daily rule moved a day) leaves every date
    # where it was — only the meal type changes.
    shifts = lambda do |date|
      if pattern_type == "interval"
        (offset % interval_days).nonzero?
      else
        offset.nonzero? && date.wday == from.wday
      end
    end

    transaction do
      # Later dates move first (or earlier first, moving back) so a shifted
      # occurrence never trips over one that's about to move out of its way.
      later = recurring_meal_occurrences.includes(:meal).where(date: from..).order(date: offset.positive? ? :desc : :asc)

      later.each do |occurrence|
        attached = occurrence.meal if occurrence.meal&.recurring_meal_id == id
        next if attached == meal

        if shifts.(occurrence.date)
          new_date = occurrence.date + offset
          if recurring_meal_occurrences.where(date: new_date).where.not(id: occurrence.id).exists?
            occurrence.destroy!
            attached&.destroy!
            next
          end
          occurrence.update!(date: new_date)
          attached&.update!(date: new_date, meal_name: to_meal_name)
        else
          attached&.update!(meal_name: to_meal_name)
        end
      end

      # The dragged meal's own occurrence — dropped instead when the rule
      # already has one on the new date (the meal stays attached regardless).
      # When the rule's dates don't shift it stays put, so the old date isn't
      # generated again.
      if (own = recurring_meal_occurrences.find_by(meal: meal)) && shifts.(from)
        if recurring_meal_occurrences.where(date: to_date).where.not(id: own.id).exists?
          own.destroy!
        else
          own.update!(date: to_date)
        end
      end
      meal.update!(date: to_date, meal_name: to_meal_name)

      self.meal_name = to_meal_name
      if pattern_type == "interval"
        self.start_date += offset if shifts.(from)
      elsif shifts.(from)
        self.days_of_week = (days_of_week - [ from.wday ] + [ to_date.wday ]).uniq.sort
      end
      save!
    end
  end

  def description
    case pattern_type
    when "interval"
      interval_days == 1 ? "Every day" : "Every #{interval_days} days"
    when "days_of_week"
      "Weekly on " + days_of_week.sort.map { |wday| Date::ABBR_DAYNAMES[wday] }.join(", ")
    end
  end

  # Meals this rule generated that are still attached (not individually
  # detached) and dated today or later — what "remove upcoming meals too"
  # on delete would actually clear.
  def upcoming_meals
    meals.where("date >= ?", Date.current)
  end

  def date_range_description
    if end_date.nil?
      "Starting #{start_date.strftime('%b %d')} · ongoing"
    else
      "#{start_date.strftime('%b %d')} – #{end_date.strftime('%b %d')}"
    end
  end

  private

  def apply_end_type
    case end_type
    when "week"    then self.end_date = start_date&.end_of_week
    when "ongoing" then self.end_date = nil
    end
    # "date" (or blank end_type on a direct model update) leaves end_date as
    # already assigned.
  end

  def normalize_days_of_week
    return unless days_of_week.is_a?(Array)

    self.days_of_week = days_of_week.reject(&:blank?).map(&:to_i)
  end

  def days_of_week_present
    errors.add(:days_of_week, "can't be blank") if days_of_week.blank?
  end

  def end_date_not_before_start_date
    return unless start_date && end_date

    errors.add(:end_date, "can't be before the start date") if end_date < start_date
  end
end
