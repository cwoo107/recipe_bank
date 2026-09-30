require "test_helper"
require_relative "../support/stripe_test_helper"

class StripeEventJobTest < ActiveJob::TestCase
  include StripeTestHelper
  include ActionMailer::TestHelper

  test "each event is applied once, however often Stripe sends it" do
    households(:one).update!(stripe_customer_id: "cus_123")
    event = stripe_event("invoice.payment_failed", Stripe::Invoice.construct_from(id: "in_1", customer: "cus_123"), id: "evt_once")

    Stripe::Event.stub(:retrieve, event) do
      assert_emails 1 do
        StripeEventJob.perform_now("evt_once")
        StripeEventJob.perform_now("evt_once")
      end
    end
    assert_equal 1, StripeEvent.where(event_id: "evt_once").count
  end
end
