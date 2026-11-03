# Everything that talks to Stripe: starting Checkout, opening the Customer
# Portal, and turning webhook events into household billing state.
#
# Stripe owns the subscription; the household keeps a copy of what matters
# for access (Household::Billing). Every sync re-reads the subscription from
# Stripe rather than trusting an event's payload, so events arriving late,
# twice or out of order all end in the same place.
module StripeBilling
  # Stripe won't start a subscription trial that ends less than 48 hours out
  # (it'd rather charge now), so a trial closer to its end than this isn't
  # carried into Checkout.
  MIN_TRIAL_CARRYOVER = 48.hours

  # Stripe caps a trial at two years out. Free time past this isn't given
  # at Checkout; a referral reward that would go past it waits in the
  # household's bank instead (grant_free_months).
  MAX_TRIAL = 729.days

  # The launch list's three free months: a quarter off the first annual
  # payment ($39 instead of $52), after the usual free month. Made in Stripe
  # the first time it's needed (launch_coupon_id).
  #
  # Repeating rather than "once": with a trial, a subscription's first
  # invoice is the $0 one at sign-up, which can use a "once" coupon up. Six
  # months covers the first annual payment (at most a month or so after
  # Checkout, later only if referral months push it) and never the renewal.
  LAUNCH_COUPON = {
    id: "launch-list-annual", name: "Launch list: 3 months free",
    percent_off: 25, duration: "repeating", duration_in_months: 6
  }.freeze

  # Subscriptions that are over — a household with one of these can start a
  # fresh Checkout.
  ENDED_STATUSES = %w[canceled incomplete_expired].freeze

  HANDLED_EVENTS = %w[
    checkout.session.completed
    customer.subscription.created
    customer.subscription.updated
    customer.subscription.deleted
    customer.subscription.paused
    customer.subscription.resumed
    invoice.payment_failed
    invoice.paid
  ].freeze

  class NotConfigured < StandardError; end

  module_function

  def config = Rails.application.config.x.stripe

  # All four settings present (see config/initializers/stripe.rb).
  def configured?
    config.secret_key.present? && config.webhook_secret.present? && config.prices.values.all?(&:present?)
  end

  # The URL of a Checkout page for the plan. Any free days left carry over,
  # so subscribing early never costs the rest of the trial, and free months
  # banked from referrals go on top. A launch household choosing annual gets
  # the launch discount — in place of promotion codes, which Stripe won't
  # take alongside one.
  def checkout_url(household, plan:, success_url:, cancel_url:)
    ensure_configured!
    price = config.prices.fetch(plan)

    trial_end = free_until(household, plan:)
    banked = household.free_months_banked
    launch_discount = household.launch_offer? && plan == "annual"
    subscription_data = { metadata: { household_id: household.id } }
    subscription_data[:metadata][:launch_discount] = "1" if launch_discount
    if trial_end && trial_end > MIN_TRIAL_CARRYOVER.from_now
      subscription_data[:trial_end] = [ trial_end, MAX_TRIAL.from_now ].min.to_i
    end
    promotion = launch_discount ? { discounts: [ { coupon: launch_coupon_id } ] } : { allow_promotion_codes: true }

    Stripe::Checkout::Session.create(
      mode: "subscription",
      customer: customer_id_for(household),
      client_reference_id: household.id.to_s,
      line_items: [ { price:, quantity: 1 } ],
      subscription_data:,
      # Read back once Checkout completes (handle): the banked months it
      # used, and whether it took the launch discount.
      metadata: { household_id: household.id, free_months_used: subscription_data.key?(:trial_end) ? banked : 0,
                  launch_discount: launch_discount ? "1" : "0" },
      **promotion,
      success_url:,
      cancel_url:
    ).url
  end

  # When a subscription to `plan` started now would make its first charge,
  # or nil to charge straight away. (The same for either plan today.)
  def free_until(household, plan:)
    trial_end = household.trial_ends_at if household.on_trial?
    trial_end = [ trial_end, Time.current ].compact.max + household.free_months_banked.months if household.free_months_banked.positive?
    trial_end
  end

  # The launch coupon (LAUNCH_COUPON), made the first time it's needed —
  # test and live mode each have their own.
  def launch_coupon_id
    Stripe::Coupon.retrieve(LAUNCH_COUPON[:id]).id
  rescue Stripe::InvalidRequestError
    Stripe::Coupon.create(LAUNCH_COUPON).id
  end

  # Free months on top of the household's plan — a referral reward. A live
  # subscription's next payment moves back (the rest of what's been paid
  # for is kept, and the months are added after it); without one they're
  # banked until it subscribes (checkout_url).
  def grant_free_months(household, months)
    if household.stripe_subscription_id.present? && %w[active trialing].include?(household.subscription_status)
      ensure_configured!
      subscription = Stripe::Subscription.retrieve(household.stripe_subscription_id)
      next_charge = subscription.status == "trialing" ? subscription.trial_end : subscription.items.data.first.current_period_end
      pushed_to = Time.zone.at(next_charge) + months.months

      if pushed_to < MAX_TRIAL.from_now
        Stripe::Subscription.update(subscription.id, trial_end: pushed_to.to_i, proration_behavior: "none")
        return sync(household, subscription.id)
      end
    end

    household.increment!(:free_months_banked, months)
  end

  # The Customer Portal: switch plans, cancel, update the card, invoices.
  def portal_url(household, return_url:)
    ensure_configured!
    raise ArgumentError, "household has no Stripe customer" if household.stripe_customer_id.blank?

    Stripe::BillingPortal::Session.create(customer: household.stripe_customer_id, return_url:).url
  end

  # The household's Stripe customer, created the first time it's needed.
  # The idempotency key stops a double-click making two.
  def customer_id_for(household)
    return household.stripe_customer_id if household.stripe_customer_id.present?

    customer = Stripe::Customer.create(
      { email: household.owner.email, name: household.family_name, metadata: { household_id: household.id } },
      { idempotency_key: "household-#{household.id}-customer" }
    )
    household.update!(stripe_customer_id: customer.id)
    customer.id
  end

  # ── Webhooks ────────────────────────────────────────────────────────────

  # Called by StripeEventJob with an event freshly fetched from Stripe.
  def handle(event)
    object = event.data.object

    case event.type
    when "checkout.session.completed"
      household = Household.find_by(id: object.client_reference_id)
      if household && object.subscription
        link_subscription(household, object.subscription)
        # Applied once, here — events are handled once (StripeEventJob).
        used = object.metadata&.[]("free_months_used").to_i
        household.update!(free_months_banked: [ household.free_months_banked - used, 0 ].max) if used.positive?
        # The launch discount is one per household — not again after a cancel.
        household.update!(launch_offer: false) if object.metadata&.[]("launch_discount") == "1"
      end
    when /\Acustomer\.subscription\./
      household = household_for_subscription(object)
      sync(household, object.id) if household
    when "invoice.payment_failed"
      household = Household.find_by(stripe_customer_id: object.customer)
      BillingMailer.payment_failed(household).deliver_now if household
    when "invoice.paid"
      household = Household.find_by(stripe_customer_id: object.customer)
      subscription_id = object.parent&.subscription_details&.subscription
      if household&.referral && subscription_id
        interval = Stripe::Subscription.retrieve(subscription_id).items.data.first&.price&.recurring&.interval
        Referral.record_payment(object, household:, interval:)
      end
    end
  end

  # A just-completed Checkout: this subscription is now the household's,
  # replacing any earlier one that had ended.
  def link_subscription(household, subscription_id)
    household.update!(stripe_subscription_id: subscription_id)
    sync(household, subscription_id)
  end

  # Copies the subscription's current state onto the household. Ignores
  # other subscriptions while the household's own is still live (say, a late
  # event for an older, ended one); once its own has ended, a new one takes
  # over.
  #
  # The launch discount is for the annual plan: one that switches to monthly
  # in the portal before it's used has it taken off here, so it doesn't come
  # off monthly payments instead.
  def sync(household, subscription_id)
    current = household.stripe_subscription_id
    return if current.present? && current != subscription_id && ENDED_STATUSES.exclude?(household.subscription_status)

    subscription = Stripe::Subscription.retrieve(subscription_id)
    item = subscription.items.data.first

    if subscription.metadata&.[]("launch_discount") == "1" && item&.price&.recurring&.interval == "month"
      Stripe::Subscription.delete_discount(subscription.id)
      subscription = Stripe::Subscription.update(subscription.id, metadata: { launch_discount: "removed" })
      item = subscription.items.data.first
    end

    household.update!(
      stripe_subscription_id: subscription.id,
      stripe_customer_id: subscription.customer,
      subscription_status: subscription.status,
      plan_interval: item&.price&.recurring&.interval,
      current_period_ends_at: item && Time.zone.at(item.current_period_end),
      trial_ends_at: subscription.trial_end ? Time.zone.at(subscription.trial_end) : household.trial_ends_at
    )
  end

  def household_for_subscription(subscription)
    Household.find_by(stripe_subscription_id: subscription.id) ||
      Household.find_by(id: subscription.metadata["household_id"]) ||
      Household.find_by(stripe_customer_id: subscription.customer)
  end

  # Moves a Stripe-managed trial's end (admin trial extensions). Stripe
  # doesn't charge for the extra time; the webhook would sync this too, but
  # doing it here means the admin page shows it straight away.
  def extend_trial(household, to:)
    ensure_configured!
    Stripe::Subscription.update(household.stripe_subscription_id, trial_end: to.to_i, proration_behavior: "none")
    sync(household, household.stripe_subscription_id)
  end

  # Ends the household's subscription straight away — its owner is deleting
  # their account (User::AccountDeletion).
  def cancel_subscription(household)
    return if household.stripe_subscription_id.blank? || ENDED_STATUSES.include?(household.subscription_status)

    ensure_configured!
    Stripe::Subscription.cancel(household.stripe_subscription_id)
  end

  def ensure_configured!
    raise NotConfigured, "Stripe isn't configured" unless configured?
  end
end
