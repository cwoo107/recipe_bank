# Someone who asked to hear when HomemakersHaven opens (the "Coming soon"
# home page). Signing up with the same email takes three months off the
# household's first annual payment, after the usual free month
# (Household#launch_offer, StripeBilling::LAUNCH_COUPON).
class LaunchSubscriber < ApplicationRecord
  has_secure_token :unsubscribe_token

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: true

  scope :subscribed,   -> { where(unsubscribed_at: nil) }
  scope :newest_first, -> { order(created_at: :desc) }

  # On the list before launch — whether or not they've since unsubscribed
  # from the emails, the three months were promised to them.
  def self.listed?(email)
    email.present? && exists?(email: email.to_s.strip.downcase)
  end

  def unsubscribed? = unsubscribed_at.present?

  def unsubscribe!
    update!(unsubscribed_at: Time.current) unless unsubscribed?
  end
end
