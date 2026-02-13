require "test_helper"

class HouseholdMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household_member = household_members(:one)
  end

  test "should get index" do
    get household_members_url
    assert_response :success
  end

  test "should get new" do
    get new_household_member_url
    assert_response :success
  end

  test "should create household_member" do
    assert_difference("HouseholdMember.count") do
      post household_members_url, params: { household_member: { child: @household_member.child, household_id: @household_member.household_id, name: @household_member.name } }
    end

    assert_redirected_to household_member_url(HouseholdMember.last)
  end

  test "should show household_member" do
    get household_member_url(@household_member)
    assert_response :success
  end

  test "should get edit" do
    get edit_household_member_url(@household_member)
    assert_response :success
  end

  test "should update household_member" do
    patch household_member_url(@household_member), params: { household_member: { child: @household_member.child, household_id: @household_member.household_id, name: @household_member.name } }
    assert_redirected_to household_member_url(@household_member)
  end

  test "should destroy household_member" do
    assert_difference("HouseholdMember.count", -1) do
      delete household_member_url(@household_member)
    end

    assert_redirected_to household_members_url
  end
end
