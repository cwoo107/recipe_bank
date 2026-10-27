require "test_helper"

# Before launch: public sign-up is closed (Launch), beta invite links open it
# for one person each, and anyone can join the launch mailing list — which
# earns three free months.
class PreLaunchTest < ActionDispatch::IntegrationTest
  setup do
    @was_open = Rails.application.config.x.registrations_open
    Rails.application.config.x.registrations_open = false
    @admin = users(:two).tap { |user| user.update!(app_admin: true) }
  end

  teardown do
    Rails.application.config.x.registrations_open = @was_open
  end

  def sign_up(email:)
    post user_registration_url, params: { user: { email:, password: "secret-pass-123", password_confirmation: "secret-pass-123",
                                                   household_family_name: "The Testers" } }
  end

  # ── Closed sign-up ──────────────────────────────────────────────────────

  test "the sign-up form is closed without an invite" do
    get new_user_registration_url
    assert_redirected_to root_url(anchor: "launch-list")

    assert_no_difference "User.count" do
      sign_up(email: "new@example.com")
    end
    assert_redirected_to root_url(anchor: "launch-list")
  end

  test "signing in still works" do
    get new_user_session_url
    assert_response :success
    assert_select "a[href=?]", new_user_registration_path, count: 0
    assert_select "a", text: "Join the launch list"
  end

  test "once registrations open, anyone can sign up" do
    Rails.application.config.x.registrations_open = true

    get new_user_registration_url
    assert_response :success
    assert_difference "User.count" do
      sign_up(email: "new@example.com")
    end
  end

  # ── Beta invites ────────────────────────────────────────────────────────

  test "a beta invite link opens sign-up once, and is used up by the account it makes" do
    invite = BetaInvite.create!(name: "Dana", created_by: @admin)

    get beta_invite_url(invite.token)
    assert_redirected_to new_user_registration_url
    follow_redirect!
    assert_response :success
    assert_match "Welcome to the beta, Dana", response.body

    assert_difference "User.count" do
      sign_up(email: "dana@example.com")
    end
    assert_equal User.find_by(email: "dana@example.com"), invite.reload.redeemed_by
    assert invite.redeemed?

    delete destroy_user_session_url
    get beta_invite_url(invite.token)
    assert_redirected_to root_url
    get new_user_registration_url
    assert_redirected_to root_url(anchor: "launch-list")
  end

  test "an unknown invite link doesn't open sign-up" do
    get beta_invite_url("not-a-real-token")
    assert_redirected_to root_url
    get new_user_registration_url
    assert_redirected_to root_url(anchor: "launch-list")
  end

  test "a failed sign-up keeps the invite for another try" do
    invite = BetaInvite.create!
    get beta_invite_url(invite.token)

    assert_no_difference "User.count" do
      sign_up(email: "not-an-email")
    end
    assert_not invite.reload.redeemed?

    get new_user_registration_url
    assert_response :success
  end

  test "app admins make, list and revoke invite links" do
    sign_in @admin
    assert_difference "BetaInvite.count" do
      post admin_beta_invites_url, params: { name: "Uncle Ray" }
    end
    invite = BetaInvite.last
    assert_equal @admin, invite.created_by

    get admin_beta_invites_url
    assert_response :success
    assert_select "input[value=?]", beta_invite_url(invite.token)

    assert_difference "BetaInvite.count", -1 do
      delete admin_beta_invite_url(invite)
    end
  end

  test "a used invite can't be revoked" do
    invite = BetaInvite.create!(redeemed_by: users(:one), redeemed_at: Time.current)
    sign_in @admin

    assert_no_difference "BetaInvite.count" do
      delete admin_beta_invite_url(invite)
    end
    assert_response :not_found
  end

  test "only app admins see the invite and launch list pages" do
    [ -> { get admin_beta_invites_url }, -> { post admin_beta_invites_url }, -> { get admin_launch_subscribers_url } ].each do |request|
      sign_in users(:one)
      request.call
      assert_response :not_found
    end
  end

  # ── Launch mailing list ─────────────────────────────────────────────────

  test "the home page is a Coming soon page with the launch list form" do
    get root_url
    assert_response :success
    assert_match "Coming soon", response.body
    assert_select "form[action=?] input[type=email]", launch_subscribers_path
    assert_select "a[href=?]", new_user_registration_path, count: 0
  end

  test "the feature pages, new ones included, render with the launch list" do
    %w[/features/restock /features/chores /features/plan-your-week /features/todos /pricing].each do |path|
      get path
      assert_response :success, path
      assert_select "form[action=?]", launch_subscribers_path
    end
  end

  test "joining the launch list" do
    assert_difference "LaunchSubscriber.count" do
      post launch_subscribers_url, params: { launch_subscriber: { email: "  Fan@Example.com " } }
    end
    assert_redirected_to root_url(anchor: "launch-list")
    assert_equal "fan@example.com", LaunchSubscriber.last.email

    # Again — no duplicate, and an unsubscribed one is back on.
    LaunchSubscriber.last.unsubscribe!
    assert_no_difference "LaunchSubscriber.count" do
      post launch_subscribers_url, params: { launch_subscriber: { email: "fan@example.com" } }
    end
    assert_not LaunchSubscriber.last.unsubscribed?
  end

  test "a bad email isn't added" do
    assert_no_difference "LaunchSubscriber.count" do
      post launch_subscribers_url, params: { launch_subscriber: { email: "nope" } }
    end
    assert_equal "Please enter a valid email address.", flash[:alert]
  end

  test "unsubscribing from the launch list" do
    subscriber = LaunchSubscriber.create!(email: "fan@example.com")
    get unsubscribe_launch_list_url(subscriber.unsubscribe_token)

    assert_response :success
    assert subscriber.reload.unsubscribed?
  end

  test "the launch list's CSV has the still-subscribed emails" do
    LaunchSubscriber.create!(email: "keen@example.com")
    LaunchSubscriber.create!(email: "gone@example.com").unsubscribe!
    sign_in @admin

    get admin_launch_subscribers_url(format: :csv)
    assert_response :success
    assert_match "keen@example.com", response.body
    assert_no_match "gone@example.com", response.body
  end

  test "signing up with an email from the launch list gets three free months" do
    LaunchSubscriber.create!(email: "early@example.com")
    Rails.application.config.x.registrations_open = true

    sign_up(email: "Early@Example.com")
    sign_up_household = User.find_by(email: "early@example.com").household
    assert_in_delta 3.months.from_now, sign_up_household.trial_ends_at, 1.minute

    delete destroy_user_session_url
    sign_up(email: "late@example.com")
    assert_in_delta Household::Billing::TRIAL_LENGTH.from_now, User.find_by(email: "late@example.com").household.trial_ends_at, 1.minute
  end
end
