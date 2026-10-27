# A one-person sign-up link for the beta, made by an app admin (see
# Admin::BetaInvitesController) while public sign-ups are closed
# (Launch.registrations_open?). It works once: the account made with it
# redeems it.
class BetaInvite < ApplicationRecord
  has_secure_token :token, length: 24

  belongs_to :created_by,  class_name: "User", optional: true
  belongs_to :redeemed_by, class_name: "User", optional: true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :unredeemed,   -> { where(redeemed_at: nil) }

  def self.usable(token)
    unredeemed.find_by(token: token) if token.present?
  end

  def redeemed? = redeemed_at.present?

  def redeem!(user)
    update!(redeemed_by: user, redeemed_at: Time.current)
  end
end
