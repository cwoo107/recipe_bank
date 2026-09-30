# Stripe is optional: with none of these set the app runs as before, and the
# checkout and portal buttons just say payments aren't available yet
# (StripeBilling.configured?). Nothing here is read with ENV.fetch, so a
# missing key never stops the app from booting.
#
#   STRIPE_SECRET_KEY      sk_test_… / sk_live_…
#   STRIPE_WEBHOOK_SECRET  whsec_… (from the webhook endpoint in the Dashboard)
#   STRIPE_PRICE_MONTHLY   price_… for $5 / month
#   STRIPE_PRICE_ANNUAL    price_… for $52 / year
Rails.application.config.x.stripe = ActiveSupport::OrderedOptions.new.merge!(
  secret_key:     ENV["STRIPE_SECRET_KEY"].presence,
  webhook_secret: ENV["STRIPE_WEBHOOK_SECRET"].presence,
  prices: {
    "monthly" => ENV["STRIPE_PRICE_MONTHLY"].presence,
    "annual"  => ENV["STRIPE_PRICE_ANNUAL"].presence
  }
)

Stripe.api_key = Rails.application.config.x.stripe.secret_key
