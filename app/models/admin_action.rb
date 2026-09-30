# Audit trail for what app admins do to a household's account (extend a
# trial, comp access, …) — anything that touches access or money.
class AdminAction < ApplicationRecord
  belongs_to :admin, class_name: "User"
  belongs_to :household, optional: true # kept after the household is deleted

  validates :action, presence: true
  validate :admin_is_app_admin

  def self.record!(admin:, household:, action:, details: {}, note: nil)
    create!(admin:, household:, action:, details:, note:)
  end

  private

  def admin_is_app_admin
    errors.add(:admin, "must be an app admin") unless admin&.app_admin?
  end
end
