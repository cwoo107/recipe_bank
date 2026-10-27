require "test_helper"

class AdminImpersonationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:three).tap { |user| user.update!(app_admin: true) } # carol, owner of household two
    @alice = users(:one)                                               # owner of household one
    @bob   = users(:two)                                               # limited member of household one
  end

  test "an admin sees the app as the user, with a banner, and it's logged" do
    sign_in @admin

    post admin_user_impersonation_path(@bob), params: { note: "Can't see the chore chart" }
    assert_redirected_to dashboard_path

    action = AdminAction.last
    assert_equal [ "impersonation_started", @admin, @bob, households(:one), "Can't see the chore chart" ],
                 [ action.action, action.admin, action.user, action.household, action.note ]

    get household_path
    assert_response :success
    assert_select "#impersonation_banner", text: /Viewing as bob@example.com.*Doe Household/m
    assert_select "body[data-limited]" # bob's limited-member view, not the admin's
  end

  test "anything but a GET is refused and changes nothing" do
    sign_in @admin
    post admin_user_impersonation_path(@alice)

    patch household_path, params: { household: { family_name: "Changed" } }
    assert_response :see_other
    assert_match "Read-only while viewing as alice@example.com", flash[:alert]
    assert_equal "Doe Household", households(:one).reload.family_name

    patch theme_path, params: { theme: "dark" }, as: :json
    assert_response :forbidden
    assert_equal "light", @alice.reload.theme
  end

  test "what pages write as they load is rolled back" do
    sign_in @admin
    post admin_user_impersonation_path(@alice)

    assert_no_difference -> { WeeklyPlan.count } do
      get plan_week_path
      follow_redirect!
    end
    assert_response :success
  end

  test "the billing pages, which call Stripe, are refused" do
    sign_in @admin
    post admin_user_impersonation_path(@alice)

    get complete_billing_path(session_id: "cs_test")
    assert_response :see_other
    assert_match "Read-only", flash[:alert]
  end

  test "admin pages stay the admin's own meanwhile" do
    sign_in @admin
    post admin_user_impersonation_path(@bob)

    post admin_household_comp_path(households(:one)), params: { until: 1.month.from_now.to_date.iso8601 }
    assert_redirected_to admin_household_path(households(:one))
    assert households(:one).reload.comped?
    assert_equal @admin, AdminAction.find_by(action: "comp").admin
  end

  test "stopping goes back to their admin page as the admin again" do
    sign_in @admin
    post admin_user_impersonation_path(@bob)

    delete admin_impersonation_path
    assert_redirected_to admin_user_path(@bob)
    assert_equal "impersonation_ended", AdminAction.last.action

    get household_path
    assert_select "#impersonation_banner", count: 0
    assert_select "h1, h2", text: /Smith Household/
  end

  test "it ends on its own after the timeout" do
    sign_in @admin
    post admin_user_impersonation_path(@bob)

    travel Impersonation::TIMEOUT + 1.minute do
      get household_path
      assert_select "#impersonation_banner", count: 0
      assert_equal [ "impersonation_ended", "timed_out" ], [ AdminAction.last.action, AdminAction.last.details["reason"] ]
    end
  end

  test "signing out ends it and signs the admin out" do
    sign_in @admin
    post admin_user_impersonation_path(@bob)

    delete destroy_user_session_path
    assert_equal [ "impersonation_ended", "signed_out" ], [ AdminAction.last.action, AdminAction.last.details["reason"] ]

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "no viewing as another admin" do
    @alice.update!(app_admin: true)
    sign_in @admin

    post admin_user_impersonation_path(@alice)
    assert_redirected_to admin_user_path(@alice)
    assert_nil AdminAction.find_by(action: "impersonation_started")
  end

  test "non-admins can't start one" do
    sign_in @bob
    post admin_user_impersonation_path(@alice)
    assert_response :not_found
  end
end
