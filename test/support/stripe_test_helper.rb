require "minitest/mock"

# Pretend Stripe is configured, and build Stripe objects without the network.
module StripeTestHelper
  WEBHOOK_SECRET = "whsec_test".freeze

  def with_stripe_configured
    config = Rails.application.config.x.stripe
    saved = config.to_h.deep_dup
    config.merge!(secret_key: "sk_test_123", webhook_secret: WEBHOOK_SECRET,
                  prices: { "monthly" => "price_monthly", "annual" => "price_annual" })
    yield
  ensure
    config.merge!(saved)
  end

  def stripe_subscription(id: "sub_123", customer: "cus_123", status: "active", interval: "month",
                          period_end: 1.month.from_now, trial_end: nil, household_id: nil)
    Stripe::Subscription.construct_from(
      id:, object: "subscription", customer:, status:,
      trial_end: trial_end&.to_i,
      metadata: household_id ? { household_id: household_id.to_s } : {},
      items: { object: "list", data: [ { object: "subscription_item", current_period_end: period_end.to_i,
                                         price: { object: "price", recurring: { interval: } } } ] }
    )
  end

  def stripe_event(type, object, id: "evt_#{SecureRandom.hex(4)}")
    Stripe::Event.construct_from(id:, object: "event", type:, data: { object: })
  end

  def signed_webhook_headers(payload, secret: WEBHOOK_SECRET)
    timestamp = Time.current
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    { "Stripe-Signature" => Stripe::Webhook::Signature.generate_header(timestamp, signature), "CONTENT_TYPE" => "application/json" }
  end
end
