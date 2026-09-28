require "test_helper"

class MemberLoginsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @household = households(:one)
    @alice = household_members(:alice) # owner
    @bob   = household_members(:one)   # limited, has a login
    @kid   = @household.invite_member(name: "Kid") # no login
    sign_in users(:one)
  end

  # ── Giving a member a login ──

  test "editing a member without a login offers an email field" do
    get edit_household_member_url(@kid)
    assert_select "input[name='household_member[email]']"
    assert_select "select[name='household_member[role]']"

    get edit_household_member_url(@bob)
    assert_select "input[name='household_member[email]']", count: 0
  end

  test "adding an email gives the same member a login and emails them" do
    chore = chores(:one)
    chore.update!(assignee: @kid)

    assert_emails 1 do
      patch household_member_url(@kid), params: { household_member: { name: "Kid", email: "kid@example.com", role: "limited" } }
    end

    assert_redirected_to household_url
    assert_equal "kid@example.com", @kid.reload.user.email
    assert_equal @kid, chore.reload.assignee, "same member row, so assignments carry over"
    assert_match(/can now sign in/, flash[:notice])
  end

  test "an email that's already taken shows an error and leaves them without a login" do
    assert_no_emails do
      patch household_member_url(@kid), params: { household_member: { name: "Kid", email: users(:two).email } }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: /Email has already been taken/
    assert_not @kid.reload.login?
  end

  test "saving without an email keeps them as a no-login member" do
    patch household_member_url(@kid), params: { household_member: { name: "Kiddo", email: "" } }

    assert_equal "Kiddo", @kid.reload.name
    assert_not @kid.login?
  end

  # ── Password resets ──

  test "an admin can set a member's password for them" do
    get edit_household_member_url(@bob)
    assert_select "#member_password form[action='#{update_password_household_member_path(@bob)}']"

    patch update_password_household_member_url(@bob), params: { user: { password: "newpass123", password_confirmation: "newpass123" } }

    assert_redirected_to household_url
    assert users(:two).reload.valid_password?("newpass123")
  end

  test "a mismatched password shows the error" do
    patch update_password_household_member_url(@bob), params: { user: { password: "newpass123", password_confirmation: "nope" } }

    assert_response :unprocessable_entity
    assert_select "#member_password li", text: /doesn't match/
  end

  test "an admin can email a member a reset link" do
    assert_emails 1 do
      post send_password_reset_household_member_url(@bob)
    end
    assert_match(/reset their password/, flash[:notice])
  end

  test "nobody can reset the owner's password from here" do
    @bob.update!(role: :admin)
    sign_in users(:two) # bob, now an admin

    get edit_household_member_url(@alice)
    assert_select "#member_password", count: 0

    patch update_password_household_member_url(@alice), params: { user: { password: "hijacked1", password_confirmation: "hijacked1" } }
    assert_equal "You can't change that password here.", flash[:alert]
    assert_not users(:one).reload.valid_password?("hijacked1")
  end

  test "members without a login have no password section" do
    get edit_household_member_url(@kid)
    assert_select "#member_password", count: 0
  end

  test "limited members can't reset passwords" do
    kid_login = @household.invite_member(name: "Teen", email: "teen@example.com")
    sign_in users(:two) # bob, limited

    patch update_password_household_member_url(kid_login), params: { user: { password: "newpass123", password_confirmation: "newpass123" } }
    assert_not kid_login.user.reload.valid_password?("newpass123")
  end
end
