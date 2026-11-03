require "test_helper"

# A household's share link (/r/:code): opens sign-up even before launch, and
# the household it makes is recorded as referred.
class ReferralSignUpTest < ActionDispatch::IntegrationTest
  setup do
    @was_open = Rails.application.config.x.registrations_open
    Rails.application.config.x.registrations_open = false
    @referrer = households(:one)
  end

  teardown do
    Rails.application.config.x.registrations_open = @was_open
  end

  def sign_up(email:)
    post user_registration_url, params: { user: { email:, password: "secret-pass-123", password_confirmation: "secret-pass-123",
                                                   household_family_name: "The Friends" } }
  end

  test "a share link opens sign-up before launch and records the referral" do
    get referral_link_url(@referrer.referral_code)
    assert_redirected_to new_user_registration_url

    assert_difference -> { Referral.count }, 1 do
      sign_up(email: "friend@example.com")
    end

    referral = Referral.last
    assert_equal @referrer, referral.referrer
    assert_equal User.find_by!(email: "friend@example.com").household, referral.referred
  end

  test "an unknown share link doesn't open sign-up" do
    get referral_link_url("nope1234")
    assert_redirected_to root_url

    get new_user_registration_url
    assert_redirected_to root_url(anchor: "launch-list")
  end

  test "household admins see their share link" do
    sign_in users(:one)
    get household_url

    assert_select "#referrals input[value=?]", referral_link_url(@referrer.referral_code)
  end
end
