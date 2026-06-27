class Todo < ApplicationRecord
  belongs_to :user

  acts_as_list scope: [ :user_id, :status ]

  STATUSES = %w[todo in_progress done].freeze
  PRIORITIES = { low: 1, medium: 2, high: 3, urgent: 4 }.freeze

  enum :priority, PRIORITIES, prefix: :priority

  after_initialize :set_default_priority, if: :new_record?

  validates :title,    presence: true
  validates :priority, presence: true
  validates :status,   inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position) }
  scope :by_status, ->(s) { where(status: s).ordered }

  # Human-readable helpers -----------------------------------------------

  PRIORITY_LABELS = {
    "low"    => "Low",
    "medium" => "Medium",
    "high"   => "High",
    "urgent" => "Urgent"
  }.freeze

  STATUS_LABELS = {
    "todo"        => "To Do",
    "in_progress" => "In Progress",
    "done"        => "Done"
  }.freeze

  def priority_label  = PRIORITY_LABELS[priority]
  def status_label    = STATUS_LABELS[status]

  # Move to a different column and optionally set a new position ----------

  def move_to_column!(new_status, new_position = nil)
    return if new_status == status && (new_position.nil? || new_position == position)

    old_status = status
    self.status = new_status

    # Trigger acts_as_list to rescope before saving
    remove_from_list if old_status != new_status

    if new_position
      insert_at(new_position.to_i)
    else
      move_to_bottom
    end
  end

  private

  def set_default_priority
    self.priority ||= :medium
  end
end