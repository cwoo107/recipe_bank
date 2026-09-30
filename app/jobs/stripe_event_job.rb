# Applies one Stripe webhook event (StripeWebhooksController), at most once.
# The event is re-fetched from Stripe, so what's applied is exactly what
# Stripe sent — and a Stripe hiccup just means Sidekiq retries later.
class StripeEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    return if StripeEvent.exists?(event_id:)

    event = Stripe::Event.retrieve(event_id)
    StripeEvent.transaction do
      StripeEvent.create!(event_id:, event_type: event.type)
      StripeBilling.handle(event)
    end
  rescue ActiveRecord::RecordNotUnique
    # Another worker got to it first.
  end
end
