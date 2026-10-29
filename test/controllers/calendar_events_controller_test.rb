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

  test "the form's separate date and time fields are combined" do
    post calendar_events_url, params: {
      calendar_event: {
        title: "Dentist",
        calendar_source_id: calendar_sources(:one).id,
        starts_on: "2026-11-03", starts_time: "09:15",
        ends_on: "2026-11-03", ends_time: "10:00"
      }
    }

    event = CalendarEvent.last
    assert_equal Time.zone.local(2026, 11, 3, 9, 15), event.starts_at
    assert_equal Time.zone.local(2026, 11, 3, 10, 0), event.ends_at
  end

  test "a missing start date is reported, not saved as today" do
    assert_no_difference("CalendarEvent.count") do
      post calendar_events_url, params: {
        calendar_event: {
          title: "Dentist",
          calendar_source_id: calendar_sources(:one).id,
          starts_on: "", starts_time: "09:15",
          ends_on: "2026-11-03", ends_time: "10:00"
        }
      }
    end
    assert_response :unprocessable_entity
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
