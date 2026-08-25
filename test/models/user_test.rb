require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "provisions an owned household on creation" do
    user = User.create!(email: "new.person@example.com", password: "password123")

    assert user.household.present?
    assert user.household_owner?
    assert_equal "New.Person's Household", user.household.family_name
  end

  test "does not provision a second household for a sub-user created via invite_member" do
    household = households(:one)
    member = household.invite_member(name: "Dana", email: "dana@example.com")

    refute member.user.household_owner?
    assert_equal household, member.user.household
  end
end
