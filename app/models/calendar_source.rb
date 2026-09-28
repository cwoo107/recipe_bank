class CalendarSource < ApplicationRecord
  acts_as_list scope: :household

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
  belongs_to :household

  # Secret iCal addresses work like passwords (anyone with the link sees the
  # calendar), so they're encrypted at rest — as are the OAuth token columns,
  # kept for a future account sign-in.
  encrypts :ical_url, :access_token, :refresh_token
  has_many :calendar_events, dependent: :destroy

  validates :name,     presence: true, length: { maximum: 100 }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :color,    presence: true, inclusion: { in: COLORS.keys }
  # Every provider syncs from its calendar's iCal/ICS link (the form explains
  # where each one keeps it) — there's no account sign-in.
  validates :ical_url, presence: true

  after_create :enqueue_sync, if: :syncable?
  after_update :enqueue_sync, if: -> { syncable? && saved_change_to_ical_url? }

  scope :visible,  -> { where(visible: true) }
  scope :ordered,  -> { order(:position) }

  def color_classes
    COLORS.fetch(color, COLORS["olive"])
  end

  # Any source with a URL can sync via the iCal path, regardless of provider label
  def syncable?
    ical_url.present?
  end

  def provider_label
    { "google" => "Google Calendar", "apple" => "Apple Calendar",
      "outlook" => "Outlook / Microsoft 365", "ical" => "iCal / WebCal Feed" }[provider]
  end

  def provider_icon
    { "google" => "google", "apple" => "apple", "outlook" => "microsoft", "ical" => "calendar" }[provider]
  end

  private

  def enqueue_sync
    CalendarSyncJob.perform_later(id)
  end
end