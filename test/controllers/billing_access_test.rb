require "test_helper"

class BillingAccessTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @owner  = users(:one) # alice
    @member = users(:two) # bob, a limited member
  end

  test "an expired trial sends every page to the household page's billing section" do
    @household.update!(trial_ends_at: 1.day.ago)
    sign_in @owner

    get dashboard_path
    assert_redirected_to household_path(anchor: "billing")

    get recipes_path
    assert_redirected_to household_path(anchor: "billing")

    get household_path
    assert_response :success
    assert_select "#billing_status", text: /Your free trial has ended/
    assert_select "#billing_plans form[action='#{checkout_billing_path}']", count: 2
    assert_select "#recipe_export a[href='#{household_recipe_export_path(format: :pdf)}']"
  end

  test "a locked household page shows only billing and the export" do
    @household.update!(trial_ends_at: 1.day.ago)
    sign_in @owner

    get household_path
    assert_select "#household_settings", count: 0
    assert_select "#household_members", count: 0
    assert_select "form[action='#{household_path}'] button", text: "Delete household", count: 0

    patch household_path, params: { household: { family_name: "Renamed" } }
    assert_redirected_to household_path(anchor: "billing")
    assert_equal "Doe Household", @household.reload.family_name
  end

  test "an unlocked household page has billing alongside everything else" do
    sign_in @owner

    get household_path
    assert_select "#household_settings"
    assert_select "#billing"
    assert_select "#recipe_export"
  end

  test "background requests get 402 instead of a redirect" do
    @household.update!(trial_ends_at: 1.day.ago)
    sign_in @owner

    get week_stats_meals_path, as: :json
    assert_response :payment_required
  end

  test "marketing pages, sign-out and the export stay open when locked" do
    @household.update!(trial_ends_at: 1.day.ago)
    sign_in @owner

    get pricing_path
    assert_response :success

    get household_recipe_export_path(format: :pdf)
    assert_response :success

    delete destroy_user_session_path
    assert_redirected_to root_path
  end

  test "a trialing household gets in, with no nag until the last week" do
    sign_in @owner

    get dashboard_path
    assert_response :success
    assert_select "#trial_banner", count: 0

    @household.update!(trial_ends_at: 3.days.from_now)
    get dashboard_path
    assert_select "#trial_banner", text: /3 days left/
  end

  test "limited members never see the trial banner" do
    @household.update!(trial_ends_at: 3.days.from_now)
    sign_in @member

    get recipes_path
    assert_response :success
    assert_select "#trial_banner", count: 0
  end

  test "the trial banner can be hidden for the day" do
    @household.update!(trial_ends_at: 3.days.from_now)
    sign_in @owner

    post dismiss_trial_banner_billing_path
    get dashboard_path
    assert_select "#trial_banner", count: 0
  end

  test "limited members can't pick a plan and are told to ask an admin" do
    @household.update!(trial_ends_at: 1.day.ago)
    sign_in @member

    get household_path
    assert_response :success
    assert_select "#billing_plans", count: 0
    assert_select "#recipe_export", count: 0
    assert_match "Ask your household's owner or an admin", response.body

    post checkout_billing_path, params: { plan: "monthly" }, headers: { "HTTP_REFERER" => household_url }
    assert_redirected_to household_url
    assert_match "Only household admins", flash[:alert]
  end

  test "the billing page shows a paid plan, a comp and a running trial" do
    sign_in @owner

    get household_path
    assert_select "#billing_status", text: /days left in your free trial/

    @household.update!(subscription_status: "active", plan_interval: "year", current_period_ends_at: 1.month.from_now,
                       stripe_subscription_id: "sub_123")
    get household_path
    assert_select "#billing_status", text: /Annual plan/
    assert_select "#billing_plans", count: 0

    @household.update!(subscription_status: "canceled", comped_until: 1.year.from_now)
    get household_path
    assert_select "#billing_status", text: /free access/
  end

  test "checkout is a placeholder until Stripe is wired up" do
    sign_in @owner

    post checkout_billing_path, params: { plan: "annual" }
    assert_redirected_to household_path(anchor: "billing")
    assert_match "aren't available yet", flash[:alert]
  end

  test "nothing locks when billing isn't enforced" do
    @household.update!(trial_ends_at: 1.day.ago)
    sign_in @owner

    Rails.application.config.x.billing_enforced = false
    get dashboard_path
    assert_response :success
  ensure
    Rails.application.config.x.billing_enforced = true
  end
end
