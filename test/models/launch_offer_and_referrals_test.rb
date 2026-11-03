require "test_helper"
require_relative "../support/stripe_test_helper"

# The launch list's three free months (annual only) and the referral
# program's three free months for the referrer.
class LaunchOfferAndReferralsTest < ActiveSupport::TestCase
  include StripeTestHelper

  setup do
    @household = households(:one)
    @friend    = households(:two)
  end

  def checkout_params(household, plan:)
    session_params = nil
    household.update!(stripe_customer_id: "cus_1") if household.stripe_customer_id.blank?
    with_stripe_configured do
      Stripe::Checkout::Session.stub(:create, ->(params) { session_params = params; Stripe::Checkout::Session.construct_from(url: "u") }) do
        StripeBilling.checkout_url(household, plan:, success_url: "s", cancel_url: "c")
      end
    end
    session_params
  end

  def launch_household
    @household.update!(launch_offer: true)
    @household
  end

  # ── Launch offer ────────────────────────────────────────────────────────

  test "a new household from the launch list gets the usual free month and the offer" do
    LaunchSubscriber.create!(email: users(:two).email)
    household = Household.create!(owner: users(:two), family_name: "Listed")

    assert household.launch_offer?
    assert_in_delta Household::Billing::TRIAL_LENGTH.from_now, household.trial_ends_at, 1.minute
  end

  test "annual checkout takes three months off the first year, after the free month" do
    household = launch_household
    params = nil

    Stripe::Coupon.stub(:retrieve, ->(_) { raise Stripe::InvalidRequestError.new("No such coupon", "coupon") }) do
      Stripe::Coupon.stub(:create, ->(attrs) { assert_equal 25, attrs[:percent_off]; Stripe::Coupon.construct_from(id: attrs[:id]) }) do
        params = checkout_params(household, plan: "annual")
      end
    end

    assert_equal [ { coupon: "launch-list-annual" } ], params[:discounts]
    assert_nil params[:allow_promotion_codes], "Stripe won't take promotion codes alongside a discount"
    assert_equal household.trial_ends_at.to_i, params.dig(:subscription_data, :trial_end)
    assert_equal "1", params.dig(:subscription_data, :metadata, :launch_discount)
  end

  test "monthly checkout has no launch discount" do
    params = checkout_params(launch_household, plan: "monthly")

    assert_nil params[:discounts]
    assert params[:allow_promotion_codes]
  end

  test "the discount is used up once its checkout completes" do
    household = launch_household
    session = Stripe::Checkout::Session.construct_from(client_reference_id: household.id.to_s, subscription: "sub_123",
                                                       metadata: { launch_discount: "1" })

    Stripe::Subscription.stub(:retrieve, stripe_subscription(status: "trialing", interval: "year", trial_end: 20.days.from_now)) do
      StripeBilling.handle(stripe_event("checkout.session.completed", session))
    end

    assert_not household.reload.launch_offer?
  end

  test "switching to monthly in the portal takes the launch discount off" do
    household = launch_household
    household.update!(stripe_subscription_id: "sub_123", subscription_status: "trialing", plan_interval: "year")
    switched = Stripe::Subscription.construct_from(
      **stripe_subscription(status: "trialing", interval: "month", trial_end: 20.days.from_now).to_hash,
      metadata: { launch_discount: "1" }
    )
    removed = []
    updates = []

    with_stripe_configured do
      Stripe::Subscription.stub(:retrieve, switched) do
        Stripe::Subscription.stub(:delete_discount, ->(id) { removed << id }) do
          Stripe::Subscription.stub(:update, ->(id, params) { updates << params; stripe_subscription(status: "trialing", interval: "month", trial_end: 20.days.from_now) }) do
            StripeBilling.sync(household, "sub_123")
          end
        end
      end
    end

    assert_equal [ "sub_123" ], removed
    assert_equal({ metadata: { launch_discount: "removed" } }, updates.sole)
    assert_equal "month", household.reload.plan_interval
  end

  # ── Referrals ───────────────────────────────────────────────────────────

  test "a sign-up through a share link is recorded, but not through your own" do
    assert Referral.record(@household.referral_code, household: @friend)
    assert_nil Referral.record(@household.referral_code, household: @household)
    assert_nil Referral.record("nope", household: @friend)
  end

  test "a referred household's first annual payment starts the refund window; monthly doesn't" do
    referral = Referral.create!(referrer: @household, referred: @friend)
    invoice = Stripe::Invoice.construct_from(id: "in_1", amount_paid: 5200, status_transitions: { paid_at: Time.current.to_i })

    Referral.record_payment(invoice, household: @friend, interval: "month")
    assert_nil referral.reload.paid_at

    Referral.record_payment(invoice, household: @friend, interval: "year")
    assert_in_delta Referral::REFUND_WINDOW.from_now, referral.reload.qualifies_at, 5.seconds
    assert_equal "in_1", referral.stripe_invoice_id
  end

  test "invoice.paid for a referred household records the payment" do
    referral = Referral.create!(referrer: @household, referred: @friend)
    @friend.update!(stripe_customer_id: "cus_friend")
    invoice = Stripe::Invoice.construct_from(id: "in_1", object: "invoice", customer: "cus_friend", amount_paid: 5200,
                                             status_transitions: { paid_at: Time.current.to_i },
                                             parent: { subscription_details: { subscription: "sub_friend" } })

    Stripe::Subscription.stub(:retrieve, stripe_subscription(id: "sub_friend", interval: "year")) do
      StripeBilling.handle(stripe_event("invoice.paid", invoice))
    end

    assert referral.reload.paid_at
  end

  test "a paying referrer's next payment moves back three months" do
    period_end = 2.months.from_now.change(usec: 0)
    @household.update!(stripe_subscription_id: "sub_123", subscription_status: "active", plan_interval: "month")
    pushed = nil

    with_stripe_configured do
      Stripe::Subscription.stub(:retrieve, stripe_subscription(status: "active", period_end:)) do
        Stripe::Subscription.stub(:update, ->(id, params) { pushed = params }) do
          StripeBilling.grant_free_months(@household, 3)
        end
      end
    end

    assert_equal (period_end + 3.months).to_i, pushed[:trial_end]
    assert_equal "none", pushed[:proration_behavior]
    assert_equal 0, @household.reload.free_months_banked
  end

  test "a referrer without a subscription banks the months, which go on at checkout and come off once it completes" do
    StripeBilling.grant_free_months(@household, 3)
    assert_equal 3, @household.reload.free_months_banked

    params = checkout_params(@household, plan: "monthly")
    assert_in_delta (@household.trial_ends_at + 3.months).to_i, params.dig(:subscription_data, :trial_end), 5
    assert_equal 3, params.dig(:metadata, :free_months_used)

    session = Stripe::Checkout::Session.construct_from(client_reference_id: @household.id.to_s, subscription: "sub_123",
                                                       metadata: { free_months_used: "3" })
    Stripe::Subscription.stub(:retrieve, stripe_subscription(status: "trialing", trial_end: 4.months.from_now)) do
      StripeBilling.handle(stripe_event("checkout.session.completed", session))
    end
    assert_equal 0, @household.reload.free_months_banked
  end

  test "past the refund window, the referrer is rewarded once if the household is still on annual" do
    referral = Referral.create!(referrer: @household, referred: @friend, paid_at: 31.days.ago, qualifies_at: 1.day.ago)
    @friend.update!(stripe_subscription_id: "sub_friend", subscription_status: "active", plan_interval: "year")

    with_stripe_configured do
      ReferralRewardsJob.perform_now
      ReferralRewardsJob.perform_now
    end

    assert referral.reload.rewarded_at
    assert_equal Referral::FREE_MONTHS, @household.reload.free_months_banked
  end

  test "a household that cancelled or left annual within the window earns nothing" do
    referral = Referral.create!(referrer: @household, referred: @friend, paid_at: 31.days.ago, qualifies_at: 1.day.ago)
    @friend.update!(stripe_subscription_id: "sub_friend", subscription_status: "canceled", plan_interval: "year")

    with_stripe_configured { ReferralRewardsJob.perform_now }

    assert referral.reload.voided_at
    assert_equal 0, @household.reload.free_months_banked
  end

  test "a referral still inside the window waits" do
    referral = Referral.create!(referrer: @household, referred: @friend, paid_at: 5.days.ago, qualifies_at: 25.days.from_now)
    @friend.update!(stripe_subscription_id: "sub_friend", subscription_status: "active", plan_interval: "year")

    with_stripe_configured { ReferralRewardsJob.perform_now }

    assert_nil referral.reload.rewarded_at
  end
end
