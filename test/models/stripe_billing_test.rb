require "test_helper"
require_relative "../support/stripe_test_helper"

class StripeBillingTest < ActiveSupport::TestCase
  include StripeTestHelper
  include ActionMailer::TestHelper

  setup do
    @household = households(:one)
  end

  test "configured only once every key and price is set" do
    assert_not StripeBilling.configured?
    with_stripe_configured { assert StripeBilling.configured? }
  end

  test "checkout creates the customer once and carries the trial's free days" do
    @household.update!(trial_ends_at: 10.days.from_now)
    created = []
    session_params = nil

    with_stripe_configured do
      create_customer = ->(params, opts) { created << [ params, opts ]; Stripe::Customer.construct_from(id: "cus_new") }
      create_session  = ->(params) { session_params = params; Stripe::Checkout::Session.construct_from(id: "cs_1", url: "https://checkout.stripe.com/c/cs_1") }

      Stripe::Customer.stub(:create, create_customer) do
        Stripe::Checkout::Session.stub(:create, create_session) do
          url = StripeBilling.checkout_url(@household, plan: "annual", success_url: "https://app/ok", cancel_url: "https://app/no")
          assert_equal "https://checkout.stripe.com/c/cs_1", url

          StripeBilling.checkout_url(@household, plan: "annual", success_url: "https://app/ok", cancel_url: "https://app/no")
        end
      end
    end

    assert_equal 1, created.size, "the customer is reused the second time"
    assert_equal users(:one).email, created.first.first[:email]
    assert_equal "household-#{@household.id}-customer", created.first.last[:idempotency_key]
    assert_equal "cus_new", @household.reload.stripe_customer_id

    assert_equal "cus_new", session_params[:customer]
    assert_equal [ { price: "price_annual", quantity: 1 } ], session_params[:line_items]
    assert_equal @household.id.to_s, session_params[:client_reference_id]
    assert_equal @household.trial_ends_at.to_i, session_params.dig(:subscription_data, :trial_end)
  end

  test "a trial ending within 48 hours isn't carried into checkout" do
    @household.update!(trial_ends_at: 1.day.from_now, stripe_customer_id: "cus_1")
    session_params = nil

    with_stripe_configured do
      Stripe::Checkout::Session.stub(:create, ->(params) { session_params = params; Stripe::Checkout::Session.construct_from(url: "u") }) do
        StripeBilling.checkout_url(@household, plan: "monthly", success_url: "s", cancel_url: "c")
      end
    end

    assert_nil session_params.dig(:subscription_data, :trial_end)
    assert_equal "price_monthly", session_params[:line_items].first[:price]
  end

  test "sync copies the subscription onto the household" do
    period_end = 1.year.from_now.change(usec: 0)
    subscription = stripe_subscription(status: "active", interval: "year", period_end:)

    Stripe::Subscription.stub(:retrieve, subscription) do
      StripeBilling.sync(@household, "sub_123")
    end

    @household.reload
    assert_equal [ "sub_123", "cus_123", "active", "year" ],
                 [ @household.stripe_subscription_id, @household.stripe_customer_id, @household.subscription_status, @household.plan_interval ]
    assert_equal period_end, @household.current_period_ends_at
    assert_equal "annual", @household.plan
    assert @household.paid?
  end

  test "a subscription still in its free days counts as paid, not as the app trial" do
    trial_end = 5.days.from_now.change(usec: 0)
    Stripe::Subscription.stub(:retrieve, stripe_subscription(status: "trialing", trial_end:)) do
      StripeBilling.sync(@household, "sub_123")
    end

    @household.reload
    assert_equal trial_end, @household.trial_ends_at
    assert @household.paid?
    assert_not @household.on_trial?
    assert_not @household.needs_plan?
    assert_equal "paying", @household.billing_state
    assert Household.paying.exists?(@household.id)
    assert_nil @household.due_trial_reminder
  end

  test "sync ignores another subscription while the household's own is live, but not once it's ended" do
    @household.update!(stripe_subscription_id: "sub_current", subscription_status: "active")

    Stripe::Subscription.stub(:retrieve, ->(*) { flunk "shouldn't fetch" }) do
      StripeBilling.sync(@household, "sub_old")
    end
    assert_equal "sub_current", @household.reload.stripe_subscription_id

    @household.update!(subscription_status: "canceled")
    Stripe::Subscription.stub(:retrieve, stripe_subscription(id: "sub_new")) do
      StripeBilling.sync(@household, "sub_new")
    end
    assert_equal [ "sub_new", "active" ], [ @household.reload.stripe_subscription_id, @household.subscription_status ]
  end

  test "a completed checkout links its subscription, replacing an ended one" do
    @household.update!(stripe_subscription_id: "sub_old", subscription_status: "canceled")
    session = Stripe::Checkout::Session.construct_from(id: "cs_1", client_reference_id: @household.id.to_s, subscription: "sub_new")

    Stripe::Subscription.stub(:retrieve, stripe_subscription(id: "sub_new")) do
      StripeBilling.handle(stripe_event("checkout.session.completed", session))
    end

    assert_equal [ "sub_new", "active" ], [ @household.reload.stripe_subscription_id, @household.subscription_status ]
  end

  test "subscription events find the household by subscription, metadata or customer" do
    @household.update!(stripe_customer_id: "cus_123")
    Stripe::Subscription.stub(:retrieve, stripe_subscription(status: "past_due")) do
      StripeBilling.handle(stripe_event("customer.subscription.updated", stripe_subscription(status: "past_due")))
    end
    assert_equal "past_due", @household.reload.subscription_status
    assert @household.access_allowed?, "past due keeps access while Stripe retries"

    Stripe::Subscription.stub(:retrieve, stripe_subscription(status: "canceled")) do
      StripeBilling.handle(stripe_event("customer.subscription.deleted", stripe_subscription(status: "canceled")))
    end
    assert_equal "canceled", @household.reload.subscription_status
    assert_not @household.access_allowed?
    assert @household.needs_plan?
  end

  test "a failed payment emails the owner" do
    @household.update!(stripe_customer_id: "cus_123")
    invoice = Stripe::Invoice.construct_from(id: "in_1", customer: "cus_123")

    assert_emails 1 do
      StripeBilling.handle(stripe_event("invoice.payment_failed", invoice))
    end
    email = ActionMailer::Base.deliveries.last
    assert_equal [ users(:one).email ], email.to
    assert_match "didn't go through", email.subject
  end

  test "an admin can move a Stripe-managed trial" do
    admin = users(:three).tap { |user| user.update!(app_admin: true) }
    @household.update!(stripe_subscription_id: "sub_123", subscription_status: "trialing", trial_ends_at: 3.days.from_now)
    updated = nil
    new_end = (@household.trial_ends_at + 7.days).change(usec: 0)

    with_stripe_configured do
      Stripe::Subscription.stub(:update, ->(id, params) { updated = [ id, params ] }) do
        Stripe::Subscription.stub(:retrieve, stripe_subscription(status: "trialing", trial_end: new_end)) do
          @household.extend_trial!(by: 7.days, admin:)
        end
      end
    end

    assert_equal [ "sub_123", { trial_end: new_end.to_i, proration_behavior: "none" } ], updated
    assert_equal new_end, @household.reload.trial_ends_at
  end

  test "a paying subscription's trial can't be extended" do
    admin = users(:three).tap { |user| user.update!(app_admin: true) }
    @household.update!(stripe_subscription_id: "sub_123", subscription_status: "active")

    assert_not @household.trial_extendable?
    assert_raises(ArgumentError) { @household.extend_trial!(by: 7.days, admin:) }
  end
end
