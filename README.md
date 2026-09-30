# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

- Manage billing opens Stripe's Customer Portal. If an already-subscribed household picks a plan, it goes to the portal too.
    - Webhooks (POST /stripe/webhooks):
        - Checks Stripe's signature, then hands the event to a Sidekiq job.
        - The job fetches the event and subscription fresh from Stripe and handles each event only once, so repeated deliveries don't send duplicate emails.
        - It covers completed checkouts, subscription changes and cancellations, and failed payments. A failed payment emails the owner.
    - Subscribing during the trial: the household counts as paying but stays free until the trial's end date. The billing section says "Free until X — your first payment is then," and the trial reminder emails stop.
    - Past due: access continues while Stripe retries the card, and the billing section asks the owner to update it.
    - Admin trial extension: before subscribing, it works as it did. For a household that's subscribed but still in its free days, it now moves the first charge in Stripe. It's blocked for paying households, which you'd handle    
      with credits or refunds in Stripe instead.
    - Stripe errors show a friendly "try again" message instead of an error page.

  When you set up Stripe:
    1. Create one Product with two Prices, $5/month and $52/year, starting in test mode.
    2. Add a webhook endpoint at https://<your-domain>/stripe/webhooks with these events: checkout.session.completed, customer.subscription.created, customer.subscription.updated, customer.subscription.deleted,                    
       customer.subscription.paused, customer.subscription.resumed and invoice.payment_failed. Set its API version to 2026-08-26.dahlia to match the gem.
    3. Customer Portal settings: allow switching between the two prices, cancelling and updating the card.
    4. Subscriptions → retry settings: choose how many times to retry a failed payment, and cancel the subscription after the last retry. That's what finally locks out a past-due household.
    5. On Railway, set STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PRICE_MONTHLY and STRIPE_PRICE_ANNUAL.
    6. Test locally: run stripe listen --forward-to localhost:3000/stripe/webhooks with test keys in your environment, and use a test clock to simulate the trial ending.
    7. Launch: run bin/rails billing:restart_trials through railway ssh, then set BILLING_ENFORCED=true.          