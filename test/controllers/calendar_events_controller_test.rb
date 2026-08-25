require "test_helper"

class CalendarEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = calendar_events(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should create calendar event" do
    assert_difference("CalendarEvent.count") do
      post calendar_events_url, params: {
        calendar_event: {
          title: "New event",
          calendar_source_id: calendar_sources(:one).id,
          starts_at: 1.day.from_now,
          ends_at: 1.day.from_now + 1.hour
        }
      }
    end

    assert_equal households(:one), CalendarEvent.last.household
  end

  test "another member of the same household can see the event" do
    sign_in users(:two) # bob, also in household :one

    get calendar_event_url(@event)
    assert_response :success
  end

  test "a user in a different household cannot see the event" do
    sign_in users(:three) # carol, household :two

    get calendar_event_url(@event)
    assert_response :not_found
  end
end
