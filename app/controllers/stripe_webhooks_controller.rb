# Where Stripe sends events (the endpoint set up in the Stripe Dashboard).
# Checks the signature, then hands the event's id to StripeEventJob, which
# fetches it back from Stripe and applies it — so this answers quickly and a
# failure is retried by Sidekiq rather than lost.
#
# Not an ApplicationController: no sign-in, CSRF, household or billing gate.
class StripeWebhooksController < ActionController::Base
  skip_forgery_protection

  def create
    return head :service_unavailable unless StripeBilling.configured?

    event = Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"],
                                            StripeBilling.config.webhook_secret)
    StripeEventJob.perform_later(event.id) if StripeBilling::HANDLED_EVENTS.include?(event.type)
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end
end
