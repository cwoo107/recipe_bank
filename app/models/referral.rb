# A household (referred) that signed up through another's share link
# (referrer). When the referred household's first annual payment goes
# through, the reward waits out REFUND_WINDOW; if it's still on the annual
# plan then, the referrer gets FREE_MONTHS free (ReferralRewardsJob). Only
# the referrer is rewarded.
class Referral < ApplicationRecord
  FREE_MONTHS   = 3
  REFUND_WINDOW = 30.days

  belongs_to :referrer, class_name: "Household"
  belongs_to :referred, class_name: "Household"

  validates :referred_id, uniqueness: true
  validate  :not_self_referral

  scope :waiting_on_payment, -> { where(paid_at: nil, voided_at: nil) }
  scope :due,      -> { where(rewarded_at: nil, voided_at: nil).where(qualifies_at: ..Time.current) }
  scope :rewarded, -> { where.not(rewarded_at: nil) }
  scope :pending,  -> { where(rewarded_at: nil, voided_at: nil).where.not(paid_at: nil) }

  # A new household, signed up through the share link with `code` (from the
  # session — see ReferralsController). Nothing happens for an unknown code
  # or someone's own link.
  def self.record(code, household:)
    return if code.blank? || household.nil?

    referrer = Household.find_by(referral_code: code.to_s.downcase)
    return if referrer.nil? || referrer == household || referrer.owner_id == household.owner_id

    create(referrer:, referred: household)
  end

  # invoice.paid (StripeBilling.handle): a referred household's first paid
  # annual invoice starts the refund window. Monthly payments don't count —
  # one that switches to annual later counts from its first annual payment.
  def self.record_payment(invoice, household:, interval:)
    return unless interval == "year" && invoice.amount_paid.to_i.positive?

    referral = waiting_on_payment.find_by(referred: household) or return
    paid_at = invoice.status_transitions&.paid_at ? Time.zone.at(invoice.status_transitions.paid_at) : Time.current
    referral.update!(paid_at:, qualifies_at: paid_at + REFUND_WINDOW, stripe_invoice_id: invoice.id)
  end

  # Past the refund window: rewards the referrer if the referred household
  # is still paying for the annual plan, and voids the referral if not.
  # Locked and marked first, so two runs can't reward it twice; a Stripe
  # failure rolls the mark back for the next run.
  def settle!
    with_lock do
      next unless rewarded_at.nil? && voided_at.nil?

      if referred.paid? && referred.plan == "annual"
        update!(rewarded_at: Time.current)
        StripeBilling.grant_free_months(referrer, FREE_MONTHS)
      else
        update!(voided_at: Time.current)
      end
    end
  end

  private

  def not_self_referral
    errors.add(:referred, "can't be the referrer") if referrer_id.present? && referrer_id == referred_id
  end
end
