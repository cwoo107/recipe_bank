require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "users includes the owner and logged-in members" do
    household = households(:one)
    assert_includes household.users, users(:one) # alice, owner
    assert_includes household.users, users(:two) # bob, member
  end

  test "member? is true for the owner and members, false for outsiders" do
    household = households(:one)
    assert household.member?(users(:one))
    assert household.member?(users(:two))
    refute household.member?(users(:three))
  end

  test "destroying a household destroys its planning data" do
    household = households(:one)
    meal = meals(:one)
    assert_equal household, meal.household

    assert_difference("Meal.count", -1) do
      household.destroy!
    end
  end

  test "default_family_name_for derives a name from the email" do
    user = User.new(email: "jane.doe@example.com")
    assert_equal "Jane.Doe's Household", Household.default_family_name_for(user)
  end
end
