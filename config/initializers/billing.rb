# Whether an expired trial locks a household out (Household::Billing).
# Always on in development and test. Production needs BILLING_ENFORCED=true
# *and* Stripe fully configured — so no one can be locked out while there's
# no way to pay.
Rails.application.config.after_initialize do
  Rails.application.config.x.billing_enforced =
    if Rails.env.production?
      ENV["BILLING_ENFORCED"] == "true" && StripeBilling.configured?
    else
      true
    end
end
