# The referral program: each household has a share link (/r/:code). A
# household that signs up through it is recorded as referred (Referral), and
# once its first annual payment is past the refund window the referrer gets
# three free months (ReferralRewardsJob, StripeBilling.grant_free_months).
module Household::Referrals
  extend ActiveSupport::Concern

  included do
    has_many :referrals_made, class_name: "Referral", foreign_key: :referrer_id,
                              inverse_of: :referrer, dependent: :destroy
    has_one  :referral, foreign_key: :referred_id, inverse_of: :referred, dependent: :destroy

    before_create { self.referral_code ||= self.class.new_referral_code }
  end

  class_methods do
    # Short enough to read out or type: 8 lowercase letters and digits.
    def new_referral_code
      loop do
        code = SecureRandom.alphanumeric(8).downcase
        break code unless exists?(referral_code: code)
      end
    end
  end
end
