# Audit trail for what app admins do to a household's account (extend a
# trial, comp access, viewing the app as someone, …) — anything that touches
# access or money.
class AdminAction < ApplicationRecord
  belongs_to :admin, class_name: "User"
  belongs_to :household, optional: true # kept after the household is deleted
  belongs_to :user, optional: true      # the account it was about, if one (e.g. "view as")

  validates :action, presence: true
  validate :admin_is_app_admin

  def self.record!(admin:, household:, action:, user: nil, details: {}, note: nil)
    create!(admin:, household:, user:, action:, details:, note:)
  end

  private

  def admin_is_app_admin
    errors.add(:admin, "must be an app admin") unless admin&.app_admin?
  end
end
