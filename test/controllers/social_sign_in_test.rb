require "test_helper"

# Sign in with Google / Apple (User::SocialSignIn, Users::OmniauthCallbacksController),
# naming the household afterwards (HouseholdSetupsController), and account
# settings without a current password for those accounts.
class SocialSignInTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @was_open = Rails.application.config.x.registrations_open
    Rails.application.config.x.registrations_open = true
  end

  teardown do
    OmniAuth.config.mock_auth.delete(:google_oauth2)
    OmniAuth.config.mock_auth.delete(:apple)
    OmniAuth.config.test_mode = false
    Rails.application.config.x.registrations_open = @was_open
  end

  def mock_auth(provider, uid:, email:, email_verified: true)
    OmniAuth.config.mock_auth[provider] = OmniAuth::AuthHash.new(
      provider: provider.to_s, uid:, info: { email:, email_verified: }
    )
  end

  def sign_in_with(provider)
    post "/users/auth/#{provider}"
    follow_redirect!
  end

  # ── New accounts ────────────────────────────────────────────────────────

  test "a new Google account is made without a household, then names one" do
    mock_auth(:google_oauth2, uid: "g-123", email: "New.Person@example.com")

    assert_difference [ "User.count", "Identity.count" ] do
      sign_in_with(:google_oauth2)
    end
    user = User.find_by!(email: "new.person@example.com")
    assert user.awaiting_first_password?
    assert_nil user.household
    assert_redirected_to root_path

    get dashboard_path
    assert_redirected_to household_setup_path
    follow_redirect!
    assert_response :success

    post household_setup_path, params: { household: { family_name: "  " } }
    assert_response :unprocessable_entity
    assert_nil user.reload.household

    post household_setup_path, params: { household: { family_name: "The Persons" } }
    assert_redirected_to dashboard_path
    assert_equal "The Persons", user.reload.owned_household.family_name

    get dashboard_path
    assert_response :success
    get household_setup_path
    assert_redirected_to dashboard_path
  end

  test "Apple's form_post callback is bounced to a GET so the session comes along" do
    mock_auth(:apple, uid: "a-456", email: "abc@privaterelay.appleid.com")

    post "/users/auth/apple/callback", params: { code: "xyz", state: "abc" }
    assert_response :see_other
    assert_equal "/users/auth/apple/callback?code=xyz&state=abc", response.location

    assert_difference "User.count" do
      sign_in_with(:apple)
    end
    assert User.find_by(email: "abc@privaterelay.appleid.com").identities.exists?(provider: "apple", uid: "a-456")
  end

  test "before launch, a new account needs a beta invite, which it uses up" do
    Rails.application.config.x.registrations_open = false
    mock_auth(:google_oauth2, uid: "g-123", email: "beta@example.com")

    assert_no_difference "User.count" do
      sign_in_with(:google_oauth2)
    end
    assert_redirected_to root_url(anchor: "launch-list")

    invite = BetaInvite.create!(name: "Tester")
    get beta_invite_path(invite.token)
    assert_difference "User.count" do
      sign_in_with(:google_oauth2)
    end
    assert_equal User.find_by(email: "beta@example.com"), invite.reload.redeemed_by
  end

  # ── Existing accounts ───────────────────────────────────────────────────

  test "a verified email matching an account links to it and signs in" do
    alice = users(:one).tap { |user| user.update!(password: "secret-pass-123") }
    mock_auth(:google_oauth2, uid: "g-alice", email: alice.email.upcase)

    assert_no_difference "User.count" do
      assert_difference "alice.identities.count" do
        sign_in_with(:google_oauth2)
      end
    end
    get dashboard_path
    assert_response :success

    # The next time, the identity alone finds her — even if her Google email changed.
    delete destroy_user_session_path
    mock_auth(:google_oauth2, uid: "g-alice", email: "alice-new@example.com")
    assert_no_difference [ "User.count", "Identity.count" ] do
      sign_in_with(:google_oauth2)
    end
    get dashboard_path
    assert_response :success
  end

  test "an unverified email matching an account doesn't take it over" do
    mock_auth(:apple, uid: "a-evil", email: users(:one).email, email_verified: false)

    assert_no_difference [ "User.count", "Identity.count" ] do
      sign_in_with(:apple)
    end
    assert_redirected_to new_user_session_path
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  # ── Account settings ────────────────────────────────────────────────────

  test "Google accounts change settings without a current password until they set one" do
    mock_auth(:google_oauth2, uid: "g-123", email: "new@example.com")
    sign_in_with(:google_oauth2)
    user = User.find_by!(email: "new@example.com")
    user.create_owned_household!(family_name: "The News")

    get edit_user_registration_path
    assert_select "input[name='user[current_password]']", count: 0

    put user_registration_path, params: { user: { email: "renamed@example.com", password: "", password_confirmation: "" } }
    assert_equal "renamed@example.com", user.reload.email

    put user_registration_path, params: { user: { email: "renamed@example.com", password: "chosen-pass-123", password_confirmation: "chosen-pass-123" } }
    assert user.reload.valid_password?("chosen-pass-123")
    assert_not user.awaiting_first_password?

    put user_registration_path, params: { user: { email: "again@example.com" } }
    assert_equal "renamed@example.com", user.reload.email
  end

  test "password accounts still need the current password" do
    sign_in users(:one)

    get edit_user_registration_path
    assert_select "input[name='user[current_password]']"
    put user_registration_path, params: { user: { email: "changed@example.com" } }
    assert_equal "alice@example.com", users(:one).reload.email
  end

  # ── Households ──────────────────────────────────────────────────────────

  test "a member whose household was deleted names a new one" do
    bob = users(:two)
    households(:one).destroy!
    sign_in bob

    get recipes_path
    assert_redirected_to household_setup_path
    post household_setup_path, params: { household: { family_name: "Bob's Place" } }
    assert_equal "Bob's Place", bob.reload.household.family_name
  end
end
