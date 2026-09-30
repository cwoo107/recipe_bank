# One subscription per household: the owner pays, every member gets in.
#
# A new household gets a free month with no card (trial_ends_at). After
# that it needs a paid plan — or an app admin's comp (comped_until) — to use
# the app; until then everything but the billing page and the recipe export
# is locked (ApplicationController#require_active_subscription!).
#
# subscription_status uses Stripe's words, so webhooks store them as-is
# (StripeBilling.sync). Until a household has a Stripe subscription, the
# app's own trial_ends_at is the source of truth; after that Stripe is, and
# changes (like extending a trial) go through Stripe and come back by webhook.
#
# A household that subscribes mid-trial keeps its free days: its Stripe
# subscription is "trialing" until then, and counts as paid.
module Household::Billing
  extend ActiveSupport::Concern

  TRIAL_LENGTH = 30.days

  PLANS = {
    "monthly" => { label: "Monthly", interval: "month", price_cents: 500,  per_month_cents: 500 },
    "annual"  => { label: "Annual",  interval: "year",  price_cents: 5200, per_month_cents: 433 }
  }.freeze

  # Paying (or about to be retried) — Stripe's own retry settings decide when
  # a past_due subscription finally gives up and becomes canceled.
  PAID_STATUSES = %w[active past_due].freeze

  # Reminder emails, in the order they go out (see TrialRemindersJob).
  TRIAL_REMINDERS = { "week" => 7.days, "day" => 1.day, "ended" => 0.days }.freeze

  # Billing only locks anyone out once it's switched on (BILLING_ENFORCED in
  # production — see config/initializers/billing.rb), so this can ship before
  # Stripe does.
  def self.enforced?
    Rails.application.config.x.billing_enforced
  end

  included do
    before_create :start_trial

    scope :trialing, -> { where(subscription_status: "trialing", stripe_subscription_id: nil) }

    # For the admin household list's filter — one per billing_state.
    scope :comped,        -> { where(comped_until: Time.current..) }
    scope :not_comped,    -> { where(comped_until: nil).or(where(comped_until: ...Time.current)) }
    scope :paying,        -> { not_comped.where(subscription_status: PAID_STATUSES).or(not_comped.stripe_trialing) }
    scope :on_trial,      -> { not_comped.trialing.where(trial_ends_at: Time.current..) }
    scope :trial_expired, -> { not_comped.trialing.where(trial_ends_at: [ nil, ...Time.current ]) }
    scope :lapsed,        -> { not_comped.where.not(subscription_status: PAID_STATUSES + [ "trialing" ]) }
    scope :stripe_trialing, -> { where(subscription_status: "trialing").where.not(stripe_subscription_id: nil) }
  end

  BILLING_STATES = %w[comped paying on_trial trial_expired lapsed].freeze

  # Where the household stands, in one word — the scope that would find it.
  def billing_state
    if comped? then "comped"
    elsif paid? then "paying"
    elsif on_trial? then "on_trial"
    elsif trial_expired? then "trial_expired"
    else "lapsed"
    end
  end

  def access_allowed?
    comped? || paid? || on_trial?
  end

  def comped?
    comped_until.present? && comped_until.future?
  end

  # Subscribed — including a Stripe subscription still in its free days,
  # which Stripe will start charging for when they run out.
  def paid?
    PAID_STATUSES.include?(subscription_status) || stripe_trialing?
  end

  def stripe_trialing?
    subscription_status == "trialing" && stripe_subscription_id.present?
  end

  # On the app's own free trial (not yet subscribed).
  def on_trial?
    subscription_status == "trialing" && stripe_subscription_id.blank? && trial_ends_at.present? && trial_ends_at.future?
  end

  def trial_expired?
    subscription_status == "trialing" && stripe_subscription_id.blank? && !on_trial?
  end


  # Whole days left, rounded up — "1 day left" right up to the end.
  def trial_days_left
    return 0 unless on_trial?

    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  # Hasn't picked a plan (or its last one ended or never went through).
  def needs_plan?
    !comped? && !paid?
  end

  def plan
    PLANS.find { |_, plan| plan[:interval] == plan_interval }&.first
  end

  # Only before subscribing, or while a Stripe subscription is still in its
  # free days — a paying subscription's credits and refunds happen in Stripe.
  def trial_extendable?
    stripe_subscription_id.blank? || stripe_trialing?
  end

  # Admin-only (see AdminAction). Extends from whichever is later — now or
  # the current end — so an expired trial gets the full extension. A
  # Stripe-managed trial is moved in Stripe (StripeBilling.extend_trial).
  def extend_trial!(by:, admin:, note: nil)
    raise ArgumentError, "a paying subscription's trial can't be extended" unless trial_extendable?

    from = [ trial_ends_at, Time.current ].compact.max
    transaction do
      # Logged first, so a non-admin is refused before anything reaches Stripe.
      AdminAction.record!(admin:, household: self, action: "extend_trial", note:,
                          details: { from: from.iso8601, to: (from + by).iso8601 })
      if stripe_trialing?
        StripeBilling.extend_trial(self, to: from + by)
      else
        update!(trial_ends_at: from + by, subscription_status: "trialing", trial_reminder_sent: nil)
      end
    end
  end

  # Admin-only. Free access until the given time (pass nil to end it).
  def comp!(until_time, admin:, note: nil)
    transaction do
      previous = comped_until
      update!(comped_until: until_time)
      AdminAction.record!(admin:, household: self, action: "comp", note:,
                          details: { from: previous&.iso8601, to: until_time&.iso8601 })
    end
  end

  # Which reminder is due now, if any hasn't gone out yet.
  def due_trial_reminder
    return unless subscription_status == "trialing" && stripe_subscription_id.blank? && trial_ends_at && !comped?

    due = TRIAL_REMINDERS.select { |_, before| trial_ends_at - before <= Time.current }.keys.last
    return unless due

    already = TRIAL_REMINDERS.keys.index(trial_reminder_sent)
    due if already.nil? || TRIAL_REMINDERS.keys.index(due) > already
  end

  private

  def start_trial
    self.trial_ends_at ||= TRIAL_LENGTH.from_now
  end
end
