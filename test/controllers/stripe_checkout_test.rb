require "test_helper"
require_relative "../support/stripe_test_helper"

class StripeCheckoutTest < ActionDispatch::IntegrationTest
  include StripeTestHelper

  setup do
    @household = households(:one)
    sign_in users(:one)
  end

  test "choosing a plan goes to Stripe Checkout" do
    with_stripe_configured do
      StripeBilling.stub(:checkout_url, ->(household, plan:, success_url:, cancel_url:) {
        assert_equal [ @household, "monthly" ], [ household, plan ]
        assert_equal "http://www.example.com/billing/complete?session_id={CHECKOUT_SESSION_ID}", success_url
        "https://checkout.stripe.com/c/cs_1"
      }) do
        post checkout_billing_path, params: { plan: "monthly" }
      end
    end

    assert_redirected_to "https://checkout.stripe.com/c/cs_1"
  end

  test "coming back from checkout unlocks the household straight away" do
    @household.update!(trial_ends_at: 1.day.ago)
    session = Stripe::Checkout::Session.construct_from(id: "cs_1", client_reference_id: @household.id.to_s, subscription: "sub_123")

    with_stripe_configured do
      Stripe::Checkout::Session.stub(:retrieve, session) do
        Stripe::Subscription.stub(:retrieve, stripe_subscription) do
          get complete_billing_path(session_id: "cs_1")
        end
      end
    end

    assert_redirected_to household_path(anchor: "billing")
    assert @household.reload.access_allowed?
    follow_redirect!
    assert_select "#billing_status", text: /Monthly plan/
    assert_select "#billing_plans", count: 0
  end

  test "someone else's checkout session is refused" do
    session = Stripe::Checkout::Session.construct_from(id: "cs_1", client_reference_id: households(:two).id.to_s, subscription: "sub_123")

    with_stripe_configured do
      Stripe::Checkout::Session.stub(:retrieve, session) do
        get complete_billing_path(session_id: "cs_1")
      end
    end

    assert_match "couldn't find", flash[:alert]
    assert_nil @household.reload.stripe_subscription_id
  end

  test "manage billing opens the Stripe portal; a subscribed household picking a plan goes there too" do
    @household.update!(stripe_customer_id: "cus_123", stripe_subscription_id: "sub_123", subscription_status: "active")

    with_stripe_configured do
      StripeBilling.stub(:portal_url, "https://billing.stripe.com/p/session_1") do
        post portal_billing_path
        assert_redirected_to "https://billing.stripe.com/p/session_1"

        post checkout_billing_path, params: { plan: "annual" }
        assert_redirected_to "https://billing.stripe.com/p/session_1"
      end
    end
  end

  test "a Stripe outage is a friendly message, not an error page" do
    with_stripe_configured do
      StripeBilling.stub(:checkout_url, ->(*, **) { raise Stripe::APIConnectionError, "timeout" }) do
        post checkout_billing_path, params: { plan: "monthly" }
      end
    end

    assert_redirected_to household_path(anchor: "billing")
    assert_match "couldn't reach our payment provider", flash[:alert]
  end
end
