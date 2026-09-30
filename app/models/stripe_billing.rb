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
  ].freeze

  class NotConfigured < StandardError; end

  module_function

  def config = Rails.application.config.x.stripe

  # All four settings present (see config/initializers/stripe.rb).
  def configured?
    config.secret_key.present? && config.webhook_secret.present? && config.prices.values.all?(&:present?)
  end

  # The URL of a Checkout page for the plan. Any free days left carry over,
  # so subscribing early never costs the rest of the trial.
  def checkout_url(household, plan:, success_url:, cancel_url:)
    ensure_configured!
    price = config.prices.fetch(plan)

    subscription_data = { metadata: { household_id: household.id } }
    if household.on_trial? && household.trial_ends_at > MIN_TRIAL_CARRYOVER.from_now
      subscription_data[:trial_end] = household.trial_ends_at.to_i
    end

    Stripe::Checkout::Session.create(
      mode: "subscription",
      customer: customer_id_for(household),
      client_reference_id: household.id.to_s,
      line_items: [ { price:, quantity: 1 } ],
      subscription_data:,
      metadata: { household_id: household.id },
      allow_promotion_codes: true,
      success_url:,
      cancel_url:
    ).url
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
      link_subscription(household, object.subscription) if household && object.subscription
    when /\Acustomer\.subscription\./
      household = household_for_subscription(object)
      sync(household, object.id) if household
    when "invoice.payment_failed"
      household = Household.find_by(stripe_customer_id: object.customer)
      BillingMailer.payment_failed(household).deliver_now if household
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
  def sync(household, subscription_id)
    current = household.stripe_subscription_id
    return if current.present? && current != subscription_id && ENDED_STATUSES.exclude?(household.subscription_status)

    subscription = Stripe::Subscription.retrieve(subscription_id)
    item = subscription.items.data.first

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

  def ensure_configured!
    raise NotConfigured, "Stripe isn't configured" unless configured?
  end
end
