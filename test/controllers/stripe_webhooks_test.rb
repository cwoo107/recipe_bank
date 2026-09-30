require "test_helper"
require_relative "../support/stripe_test_helper"

class StripeWebhooksTest < ActionDispatch::IntegrationTest
  include StripeTestHelper
  include ActiveJob::TestHelper

  def payload(type) = { id: "evt_1", object: "event", type:, data: { object: {} } }.to_json

  test "unconfigured, the endpoint does nothing" do
    post stripe_webhooks_path, params: payload("customer.subscription.updated"), headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :service_unavailable
  end

  test "a bad signature is rejected" do
    with_stripe_configured do
      body = payload("customer.subscription.updated")
      assert_no_enqueued_jobs do
        post stripe_webhooks_path, params: body, headers: signed_webhook_headers(body, secret: "whsec_wrong")
      end
      assert_response :bad_request
    end
  end

  test "a signed event we handle is queued by id; others are just acknowledged" do
    with_stripe_configured do
      body = payload("customer.subscription.updated")
      assert_enqueued_with(job: StripeEventJob, args: [ "evt_1" ]) do
        post stripe_webhooks_path, params: body, headers: signed_webhook_headers(body)
      end
      assert_response :ok

      body = payload("charge.refunded")
      assert_no_enqueued_jobs do
        post stripe_webhooks_path, params: body, headers: signed_webhook_headers(body)
      end
      assert_response :ok
    end
  end
end
