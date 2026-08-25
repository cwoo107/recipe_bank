require "test_helper"

class CalendarSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @source = calendar_sources(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should create calendar source" do
    assert_difference("CalendarSource.count") do
      post calendar_sources_url, params: { calendar_source: { name: "New Calendar", provider: "google", color: "olive" } }
    end

    assert_equal households(:one), CalendarSource.last.household
  end

  test "a member (not owner) of the household can load the calendar page" do
    sign_in users(:two) # bob, also in household :one

    get calendars_url
    follow_redirect!
    assert_response :success
  end

  test "a user in a different household cannot edit the source" do
    sign_in users(:three) # carol, household :two

    patch calendar_source_url(@source), params: { calendar_source: { name: "Hijacked" } }
    assert_response :not_found
  end
end
