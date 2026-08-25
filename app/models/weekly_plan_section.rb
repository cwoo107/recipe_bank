class WeeklyPlanSection < ApplicationRecord
  belongs_to :weekly_plan
  belongs_to :updated_by, class_name: "User", optional: true

  STATUSES = %w[not_started in_progress skipped done].freeze

  validates :key, presence: true, uniqueness: { scope: :weekly_plan_id }
  validates :status, inclusion: { in: STATUSES }

  def mark!(status, by:)
    update!(status: status, updated_by: by, status_changed_at: Time.current)
  end

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end
end
