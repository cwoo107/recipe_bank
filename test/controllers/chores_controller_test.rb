require "test_helper"

class ChoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chore = chores(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get chores_url
    assert_response :success
  end

  test "should create chore" do
    assert_difference("Chore.count") do
      post chores_url, params: { chore: { name: "Vacuum", frequency: "weekly" } }
    end

    assert_equal households(:one), Chore.last.household
  end

  test "should update chore" do
    patch chore_url(@chore), params: { chore: { name: "Updated" } }
    assert_redirected_to chores_url
    assert_equal "Updated", @chore.reload.name
  end

  test "update redirects to return_to when it's a local path (e.g. back to the board)" do
    patch chore_url(@chore), params: { chore: { name: "Updated" }, return_to: "/weekly_chores?date=2026-08-24" }
    assert_redirected_to "/weekly_chores?date=2026-08-24"
  end

  test "update ignores an external return_to to avoid an open redirect" do
    patch chore_url(@chore), params: { chore: { name: "Updated" }, return_to: "https://evil.example.com/phish" }
    assert_redirected_to chores_url
  end

  test "should destroy chore" do
    assert_difference("Chore.count", -1) do
      delete chore_url(@chore)
    end
  end

  test "a user in a different household cannot edit the chore" do
    sign_in users(:three) # carol, household :two

    patch chore_url(@chore), params: { chore: { name: "Should not work" } }
    assert_response :not_found
  end
end
