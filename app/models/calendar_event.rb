class CalendarEvent < ApplicationRecord
  belongs_to :calendar_source
  belongs_to :user
  belongs_to :household

  STATUSES = %w[confirmed tentative cancelled].freeze

  validates :title,     presence: true, length: { maximum: 255 }
  validates :starts_at, presence: true
  validates :ends_at,   presence: true
  validates :status,    inclusion: { in: STATUSES }
  validate  :ends_after_start

  scope :in_range, ->(from, to) {
    where("starts_at < ? AND ends_at > ?", to, from)
  }
  scope :on_day, ->(date) {
    day_start = date.beginning_of_day
    day_end   = date.end_of_day
    where("starts_at <= ? AND ends_at >= ?", day_end, day_start)
  }
  scope :confirmed,   -> { where(status: "confirmed") }
  scope :visible,     -> { joins(:calendar_source).merge(CalendarSource.visible) }
  scope :chronological, -> { order(:starts_at) }

  delegate :color_classes, :name, to: :calendar_source, prefix: :source

  def duration_minutes
    ((ends_at - starts_at) / 60).round
  end

  def multi_day?
    ends_at.to_date > starts_at.to_date
  end

  def short_time
    return "All day" if all_day?
    starts_at.strftime("%-I:%M %p").downcase
  end

  def time_range
    return "All day" if all_day?
    "#{starts_at.strftime("%-I:%M")}–#{ends_at.strftime("%-I:%M %p").downcase}"
  end

  private

  def ends_after_start
    return unless starts_at && ends_at
    errors.add(:ends_at, "must be on or after start time") if ends_at < starts_at
  end
end