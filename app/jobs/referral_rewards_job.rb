# Daily (config/schedule.yml): settles referrals whose refund window has
# passed — the referrer gets their free months, or the referral is voided if
# the household it brought in is no longer on the annual plan (Referral#settle!).
# One that fails to reach Stripe is left for the next run.
class ReferralRewardsJob < ApplicationJob
  queue_as :default

  def perform
    return unless StripeBilling.configured?

    Referral.due.includes(:referrer, :referred).find_each do |referral|
      referral.settle!
    rescue Stripe::StripeError => error
      Rails.logger.error "Referral ##{referral.id}: reward not granted (#{error.class}: #{error.message}) — will retry tomorrow"
    end
  end
end
