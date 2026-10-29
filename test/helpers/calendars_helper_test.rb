require "test_helper"

class CalendarsHelperTest < ActionView::TestCase
  def event(starts_at, ends_at, all_day: false)
    CalendarEvent.new(starts_at: starts_at, ends_at: ends_at, all_day: all_day)
  end

  test "the tooltip's when line" do
    assert_equal "Tue, Nov 3 · 9:15–10:00 am",
                 event_tooltip_when(event(Time.zone.local(2026, 11, 3, 9, 15), Time.zone.local(2026, 11, 3, 10)))

    # All-day events from feeds end at midnight the next day.
    assert_equal "Tue, Nov 3 · All day",
                 event_tooltip_when(event(Time.zone.local(2026, 11, 3), Time.zone.local(2026, 11, 4), all_day: true))
    assert_equal "Tue, Nov 3 – Thu, Nov 5",
                 event_tooltip_when(event(Time.zone.local(2026, 11, 3), Time.zone.local(2026, 11, 6), all_day: true))

    assert_equal "Tue, Nov 3, 8:00 pm – Wed, Nov 4, 9:00 am",
                 event_tooltip_when(event(Time.zone.local(2026, 11, 3, 20), Time.zone.local(2026, 11, 4, 9)))
  end
end
