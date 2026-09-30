# Actions behind the household page's Plan & billing section
# (households/_billing), open even once a trial has run out (see
# ApplicationController#require_active_subscription!). The Stripe side is in
# StripeBilling; until Stripe is configured the buttons just say so.
class BillingsController < ApplicationController
  NOT_AVAILABLE = "Online payments aren't available yet — check back soon.".freeze

  skip_before_action :require_active_subscription!
  before_action :require_household!
  before_action :require_household_admin!, only: %i[checkout complete portal]
  before_action :require_stripe!, only: %i[checkout complete portal]

  rescue_from Stripe::StripeError do |error|
    Rails.logger.error("[stripe] #{error.class}: #{error.message}")
    redirect_to billing_section, alert: "We couldn't reach our payment provider. Please try again in a moment.", status: :see_other
  end

  # Off to Stripe Checkout for the chosen plan. A household that's already
  # subscribed goes to the portal instead, to change plans there.
  def checkout
    return redirect_to(billing_section, alert: "Pick a plan.", status: :see_other) unless Household::Billing::PLANS.key?(params[:plan])
    return portal if current_household.paid?

    url = StripeBilling.checkout_url(current_household, plan: params[:plan],
                                     success_url: "#{complete_billing_url}?session_id={CHECKOUT_SESSION_ID}",
                                     cancel_url: household_url(anchor: "billing"))
    redirect_to url, allow_other_host: true, status: :see_other
  end

  # Back from a finished Checkout. The webhook records the subscription too,
  # but it may not have arrived yet — linking it here means the page is
  # already unlocked when they land on it.
  def complete
    session = Stripe::Checkout::Session.retrieve(params[:session_id].to_s)

    if session.client_reference_id == current_household.id.to_s && session.subscription
      StripeBilling.link_subscription(current_household, session.subscription)
      redirect_to billing_section, notice: "You're subscribed — thank you!", status: :see_other
    else
      redirect_to billing_section, alert: "We couldn't find that checkout.", status: :see_other
    end
  end

  # The Stripe Customer Portal: switch plans, cancel, update the card.
  def portal
    return redirect_to(billing_section, alert: "Choose a plan first.", status: :see_other) if current_household.stripe_customer_id.blank?

    redirect_to StripeBilling.portal_url(current_household, return_url: household_url(anchor: "billing")),
                allow_other_host: true, status: :see_other
  end

  # Hides the trial banner for the rest of the day.
  def dismiss_trial_banner
    cookies[:trial_banner_dismissed] = { value: Date.current.iso8601, expires: Time.current.end_of_day }
    redirect_back_or_to dashboard_path, status: :see_other
  end

  private

  def require_stripe!
    redirect_to billing_section, alert: NOT_AVAILABLE, status: :see_other unless StripeBilling.configured?
  end

  def billing_section
    household_path(anchor: "billing")
  end
end
