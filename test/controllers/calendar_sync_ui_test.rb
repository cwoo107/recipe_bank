require "test_helper"

class CalendarSyncUiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @household = households(:one)
    @source = @household.calendar_sources.create!(name: "Family", provider: "google", color: "seafoam",
                                                  user: users(:one), ical_url: "https://calendar.example.com/family.ics")
    sign_in users(:one)
  end

  # ── Sidebar: status, Sync now, visibility ──

  test "the sidebar shows each calendar's sync status and a Sync now button" do
    @source.update_columns(last_synced_at: 2.hours.ago, last_sync_attempted_at: 2.hours.ago)
    get month_calendars_url(year: 2026, month: 10)

    assert_select "#source_#{@source.id}_status", text: /Synced about 2 hours ago/
    assert_select "form[action='#{sync_calendar_source_path(@source)}']"
  end

  test "a failed sync shows in the sidebar with the reason" do
    @source.update_columns(last_sync_error: "The calendar link returned an error (404).", last_sync_attempted_at: 5.minutes.ago)
    get month_calendars_url(year: 2026, month: 10)

    assert_select "#source_#{@source.id}_status span[title='The calendar link returned an error (404).']", text: /Couldn't sync/
  end

  test "Sync now queues a sync and shows it's syncing" do
    assert_enqueued_with(job: CalendarSyncJob, args: [ @source.id ]) do
      post sync_calendar_source_url(@source), as: :turbo_stream
    end
    assert_response :success
    assert_match(/Syncing…/, response.body)
  end

  test "hiding a calendar refreshes the page so its events disappear" do
    patch toggle_visible_calendar_source_url(@source), as: :turbo_stream

    assert_not @source.reload.visible?
    assert_select "turbo-stream[action=refresh]"
  end

  test "every calendar page has a Sync now button in the header, at every screen size" do
    [ month_calendars_url(year: 2026, month: 10), week_calendars_url, day_calendars_url ].each do |url|
      get url
      assert_select "form[action='#{sync_all_calendar_sources_path}'] button", text: /Sync now/
      assert_select "aside form[action='#{sync_all_calendar_sources_path}']", count: 0, message: "not tucked in the wide-screen-only sidebar"
    end
  end

  test "Sync now in the header syncs every linked calendar" do
    other = @household.calendar_sources.create!(name: "Work", provider: "outlook", color: "mist",
                                                user: users(:one), ical_url: "https://calendar.example.com/work.ics")
    clear_enqueued_jobs

    post sync_all_calendar_sources_url, headers: { "HTTP_REFERER" => week_calendars_url }

    assert_redirected_to week_calendars_url
    assert_enqueued_jobs 2 + calendar_sources(:one).then { |s| s.syncable? ? 1 : 0 }, only: CalendarSyncJob
    assert_match(/Syncing \d calendars/, flash[:notice])
    assert other
  end

  test "limited members don't get Sync now" do
    sign_in users(:two)
    get month_calendars_url(year: 2026, month: 10)
    assert_select "form[action='#{sync_calendar_source_path(@source)}']", count: 0
    assert_select "form[action='#{sync_all_calendar_sources_path}']", count: 0

    clear_enqueued_jobs # creating the calendar in setup queued its first sync
    post sync_all_calendar_sources_url
    assert_no_enqueued_jobs only: CalendarSyncJob
  end

  # ── Linking a calendar ──

  test "every provider needs its feed link, since there's no account sign-in" do
    %w[google outlook apple ical].each do |provider|
      source = @household.calendar_sources.new(name: "X", provider:, color: "olive", user: users(:one))
      assert_not source.valid?, provider
      assert_includes source.errors[:ical_url], "can't be blank"
    end
  end

  test "feed links are encrypted in the database" do
    raw = ActiveRecord::Base.connection.select_value("SELECT ical_url FROM calendar_sources WHERE id = #{@source.id}")
    assert_no_match(/calendar\.example\.com/, raw)
    assert_equal "https://calendar.example.com/family.ics", @source.reload.ical_url
  end

  test "there's no separate calendars list page (the sidebar is the list)" do
    get "/calendar_sources"
    assert_response :not_found
  end

  # ── Events ──

  test "events can be added and edited in the app" do
    get new_calendar_event_url
    assert_response :success
    assert_select "form[action='#{calendar_events_path}']"

    post calendar_events_url, params: { calendar_event: { title: "Dentist", calendar_source_id: @source.id,
                                                          starts_at: "2026-10-05T09:00", ends_at: "2026-10-05T10:00" } }
    event = CalendarEvent.find_by!(title: "Dentist")
    assert_redirected_to day_calendars_url(date: event.starts_at.to_date)

    get edit_calendar_event_url(event)
    assert_response :success

    patch calendar_event_url(event), params: { calendar_event: { title: "Dentist (moved)" } }
    assert_equal "Dentist (moved)", event.reload.title
  end

  test "synced events are read-only here — the next sync would undo changes" do
    synced = @household.calendar_events.create!(calendar_source: @source, user: users(:one), title: "From Google",
                                                external_uid: "abc", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

    get calendar_event_url(synced)
    assert_select "p", text: /From Family — to change it, edit it in that calendar/
    assert_select "a", text: "Edit", count: 0

    patch calendar_event_url(synced), params: { calendar_event: { title: "Changed" } }
    assert_equal "From Google", synced.reload.title
    assert_match(/change it there/, flash[:alert])

    assert_no_difference("CalendarEvent.count") { delete calendar_event_url(synced) }
  end

  # ── Time zone ──

  test "the household takes an admin's browser time zone the first time" do
    @household.update_columns(time_zone: nil)
    cookies[:browser_timezone] = "America/Denver"

    get dashboard_url
    assert_equal "America/Denver", @household.reload.time_zone
  end

  test "a limited member's browser doesn't set it, and a saved zone isn't overwritten" do
    @household.update_columns(time_zone: nil)
    sign_in users(:two)
    cookies[:browser_timezone] = "Asia/Tokyo"
    get dashboard_url
    assert_nil @household.reload.time_zone

    @household.update_columns(time_zone: "America/Chicago")
    sign_in users(:one)
    get dashboard_url
    assert_equal "America/Chicago", @household.reload.time_zone
  end

  test "the time zone is editable in household settings" do
    get household_url
    assert_select "#household_settings select[name='household[time_zone]'] option[value='America/Denver']"

    patch household_url, params: { household: { time_zone: "America/New_York" } }
    assert_equal "America/New_York", @household.reload.time_zone

    patch household_url, params: { household: { time_zone: "Mars/Olympus_Mons" } }
    assert_response :unprocessable_entity
    assert_equal "America/New_York", @household.reload.time_zone
  end

  test "pages use the household's zone, not the viewer's browser" do
    @household.update_columns(time_zone: "America/Denver")
    cookies[:browser_timezone] = "Asia/Tokyo"
    travel_to Time.utc(2026, 10, 6, 3) # Oct 5, 9pm in Denver; Oct 6 midday in Tokyo

    get day_calendars_url
    assert_select "h1, h2, p", text: /October 5|Oct 5/
  end
end
