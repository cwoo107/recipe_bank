class CalendarSource < ApplicationRecord
  acts_as_list scope: :user

  PROVIDERS = %w[google apple outlook ical].freeze

  COLORS = {
    "olive"      => { bg: "bg-olive-500",      ring: "ring-olive-600/30",      text: "text-olive-800",      dot: "bg-olive-500"      },
    "seafoam"    => { bg: "bg-seafoam-400",     ring: "ring-seafoam-600/30",    text: "text-seafoam-800",    dot: "bg-seafoam-500"    },
    "honey"      => { bg: "bg-honey-400",       ring: "ring-honey-600/30",      text: "text-honey-800",      dot: "bg-honey-500"      },
    "mist"       => { bg: "bg-mist-400",        ring: "ring-mist-600/30",       text: "text-mist-800",       dot: "bg-mist-500"       },
    "mauve"      => { bg: "bg-mauve-400",       ring: "ring-mauve-600/30",      text: "text-mauve-800",      dot: "bg-mauve-500"      },
    "dusty-rose" => { bg: "bg-dusty-rose-400",  ring: "ring-dusty-rose-600/30", text: "text-dusty-rose-800", dot: "bg-dusty-rose-500" }
  }.freeze

  belongs_to :user
  has_many :calendar_events, dependent: :destroy

  validates :name,     presence: true, length: { maximum: 100 }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :color,    presence: true, inclusion: { in: COLORS.keys }
  validates :ical_url, presence: true, if: -> { %w[ical apple].include?(provider) }

  after_create :enqueue_initial_sync, if: :syncable?

  scope :visible,  -> { where(visible: true) }
  scope :ordered,  -> { order(:position) }

  def color_classes
    COLORS.fetch(color, COLORS["olive"])
  end

  def needs_oauth?
    %w[google outlook].include?(provider)
  end

  def ical_feed?
    %w[ical apple].include?(provider)
  end

  def syncable?
    ical_feed? && ical_url.present?
  end

  def token_expired?
    token_expires_at.present? && token_expires_at < Time.current
  end

  def provider_label
    { "google" => "Google Calendar", "apple" => "Apple Calendar",
      "outlook" => "Outlook / Microsoft 365", "ical" => "iCal / WebCal Feed" }[provider]
  end

  def provider_icon
    { "google" => "google", "apple" => "apple", "outlook" => "microsoft", "ical" => "calendar" }[provider]
  end

  private

  def enqueue_initial_sync
    CalendarSyncJob.perform_later(id)
  end
end