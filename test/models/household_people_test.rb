require "test_helper"

class HouseholdPeopleTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  setup do
    @household = households(:one) # alice (owner) + bob, family size 3
  end

  test "a new household gets a member row for its owner" do
    user = User.create!(email: "dana@example.com", password: "password123")

    owner_member = user.household.owner_member
    assert owner_member.owner?
    assert owner_member.admin?
    assert_equal "Dana", owner_member.name
    assert_equal user.household, user.household_membership.household
  end

  test "the owner's member row can't be removed or demoted" do
    owner_member = household_members(:alice)

    assert_not owner_member.destroy
    assert HouseholdMember.exists?(owner_member.id)
    assert_not owner_member.update(role: :limited)
  end

  test "adding a member without an email adds them with no login" do
    assert_no_difference("User.count") do
      assert_no_emails do
        member = @household.invite_member(name: "Kid", email: "")
        assert member.persisted?
        assert_not member.login?
      end
    end
  end

  test "listing more people than the family size bumps it" do
    @household.invite_member(name: "Kid one")
    assert_equal 3, @household.reload.family_size, "3 listed fits a family of 3"

    @household.invite_member(name: "Kid two")
    assert_equal 4, @household.reload.family_size
  end

  test "family size can't go below the people listed" do
    assert_not @household.update(family_size: 1)
    assert_includes @household.errors[:family_size].first, "2 people listed"
    assert @household.update(family_size: 2)
  end

  test "assignment controls only apply once someone besides the owner is listed" do
    assert @household.assignable?

    solo = User.create!(email: "solo@example.com", password: "password123").household
    assert_not solo.assignable?
  end

  test "people lists the owner first" do
    @household.invite_member(name: "Aaron")
    assert_equal "Alice", @household.people.first.name
  end
end
