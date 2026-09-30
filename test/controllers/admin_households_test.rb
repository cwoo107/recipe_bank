require "test_helper"

class AdminHouseholdsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:three).tap { |user| user.update!(app_admin: true) } # carol, owner of household two
    @household = households(:one)
  end

  test "non-admins get a 404 everywhere under /admin" do
    # (A 404 doesn't save the session, so sign in again before each request.)
    sign_in users(:one)
    get admin_root_path
    assert_response :not_found

    sign_in users(:one)
    post admin_household_trial_extension_path(@household), params: { days: 30 }
    assert_response :not_found

    sign_in users(:one)
    post admin_household_comp_path(@household), params: { until: 1.year.from_now.to_date.iso8601 }
    assert_response :not_found
    assert_nil @household.reload.comped_until
  end

  test "signed-out visitors are sent to sign in" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "the list searches by name or owner email and filters by billing state" do
    households(:two).update!(trial_ends_at: 1.day.ago)
    sign_in @admin

    get admin_households_path
    assert_select "#admin_households tbody tr", count: 2

    get admin_households_path(q: "ALICE@")
    assert_select "#admin_households tbody tr", count: 1
    assert_select "#admin_households", text: /Doe Household/

    get admin_households_path(q: "smith")
    assert_select "#admin_households", text: /Smith Household/
    assert_select "#admin_households", text: /Trial ended/

    get admin_households_path(state: "trial_expired")
    assert_select "#admin_households tbody tr", count: 1
    assert_select "#admin_households", text: /Smith Household/
  end

  test "admins still get in when their own household is locked" do
    households(:two).update!(trial_ends_at: 1.day.ago)
    sign_in @admin

    get admin_household_path(@household)
    assert_response :success
    assert_select "h1", text: "Doe Household"
    assert_select "#admin_history", text: /No admin changes yet/
  end

  test "extending a trial" do
    freeze_time do
      @household.update!(trial_ends_at: 2.days.ago)
      sign_in @admin

      post admin_household_trial_extension_path(@household), params: { days: 10, note: "Was travelling" }

      assert_redirected_to admin_household_path(@household)
      assert_equal 10.days.from_now, @household.reload.trial_ends_at
      follow_redirect!
      assert_select "#admin_history", text: /Extended the trial/
      assert_select "#admin_history", text: /Was travelling/
    end
  end

  test "trial extensions are bounded and skip paying households" do
    sign_in @admin

    assert_no_changes -> { @household.reload.trial_ends_at } do
      post admin_household_trial_extension_path(@household), params: { days: 0 }
    end
    assert_match "between 1 and", flash[:alert]

    @household.update!(stripe_subscription_id: "sub_123", subscription_status: "active")
    assert_no_changes -> { @household.reload.trial_ends_at } do
      post admin_household_trial_extension_path(@household), params: { days: 10 }
    end
    assert_match "is paying", flash[:alert]
  end

  test "giving and ending free access unlocks and relocks the household" do
    @household.update!(trial_ends_at: 1.day.ago)
    sign_in @admin

    post admin_household_comp_path(@household), params: { until: (Date.current + 30).iso8601, note: "Beta tester" }
    assert @household.reload.comped?
    assert @household.access_allowed?

    delete admin_household_comp_path(@household)
    assert_not @household.reload.access_allowed?

    follow_redirect!
    assert_select "#admin_history li", count: 2
    assert_select "#admin_history", text: /Ended free access/
  end

  test "free access needs a future date" do
    sign_in @admin

    post admin_household_comp_path(@household), params: { until: Date.yesterday.iso8601 }
    assert_nil @household.reload.comped_until
    assert_match "future", flash[:alert]
  end

  test "the account menu links admins to the admin pages" do
    sign_in @admin
    get admin_root_path
    assert_select "a[href='#{admin_root_path}']", text: "Admin"

    sign_in users(:one)
    get dashboard_path
    assert_select "a[href='#{admin_root_path}']", count: 0
  end
end
