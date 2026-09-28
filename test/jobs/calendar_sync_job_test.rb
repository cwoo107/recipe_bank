require "test_helper"

class CalendarSyncJobTest < ActiveJob::TestCase
  DENVER = ActiveSupport::TimeZone["America/Denver"]

  setup do
    travel_to Time.utc(2026, 10, 1, 12) # sync window: Jul 1 2026 – Oct 1 2027
    @household = households(:one)
    @household.update!(time_zone: "America/Denver")
    @source = @household.calendar_sources.create!(name: "Family", provider: "google", color: "seafoam",
                                                  user: users(:one), ical_url: "https://calendar.example.com/family.ics")
    clear_enqueued_jobs
  end

  # Runs the real job with the feed body swapped in for the network fetch.
  def sync_with(body)
    Class.new(CalendarSyncJob) do
      define_method(:fetch) { |_url| body.respond_to?(:call) ? body.call : body }
    end.perform_now(@source.id)
    @source.reload
  end

  def events(title) = @source.calendar_events.where(title:).order(:starts_at)

  test "a weekly series that started long ago is expanded into each week in the window" do
    sync_with file_fixture("recurring.ics").read

    standups = events("Standup")
    assert_operator standups.count, :>, 40
    assert standups.all? { |e| e.starts_at.in_time_zone(DENVER).strftime("%a %H:%M") == "Mon 09:00" },
           "9am local every week, before and after daylight saving ends"
    assert_equal DENVER.local(2026, 7, 6, 9), standups.first.starts_at
    assert standups.all? { |e| e.ends_at - e.starts_at == 1.hour }
  end

  test "excluded, moved and cancelled occurrences follow the feed" do
    sync_with file_fixture("recurring.ics").read
    days = ->(title) { events(title).map { |e| e.starts_at.in_time_zone(DENVER).to_date } }

    assert_not_includes days.("Standup"), Date.new(2026, 10, 12), "EXDATE"
    assert_not_includes days.("Standup"), Date.new(2026, 10, 26), "cancelled occurrence"
    assert_not_includes days.("Standup"), Date.new(2026, 10, 19), "moved occurrence replaces the original"

    moved = events("Standup (moved)").sole
    assert_equal DENVER.local(2026, 10, 19, 11), moved.starts_at
    assert_equal "weekly-1::2026-10-19T15:00:00Z", moved.external_uid
  end

  test "all-day occurrences are midnight in the household's zone" do
    sync_with file_fixture("recurring.ics").read

    rent = events("Pay rent")
    assert_equal [ DENVER.local(2026, 10, 1), DENVER.local(2026, 11, 1), DENVER.local(2026, 12, 1) ], rent.map(&:starts_at)
    assert rent.all?(&:all_day?)
    assert_equal DENVER.local(2026, 10, 1).end_of_day.to_i, rent.first.ends_at.to_i
    assert_equal "FREQ=MONTHLY;COUNT=3", rent.first.recurrence_rule
  end

  test "times with no zone are read as the household's local time" do
    sync_with <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:floating-1
      DTSTART:20261005T180000
      DTEND:20261005T190000
      SUMMARY:Dinner out
      END:VEVENT
      END:VCALENDAR
    ICS

    assert_equal DENVER.local(2026, 10, 5, 18), events("Dinner out").sole.starts_at
  end

  test "events removed from the feed are removed here; events added in the app are kept" do
    manual = @household.calendar_events.create!(calendar_source: @source, user: users(:one), title: "Added here",
                                                starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour)
    sync_with file_fixture("recurring.ics").read
    assert events("Pay rent").any?

    sync_with "BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n"

    assert_empty events("Pay rent")
    assert_empty events("Standup")
    assert CalendarEvent.exists?(manual.id)
  end

  test "a successful sync clears any earlier error" do
    @source.update!(last_sync_error: "old problem")
    sync_with file_fixture("recurring.ics").read

    assert_nil @source.last_sync_error
    assert @source.synced?
    assert_in_delta Time.current, @source.last_synced_at, 1
  end

  test "a feed that can't be fetched records the error instead of looking synced" do
    @source.update_columns(last_synced_at: 1.day.ago, synced: true)
    sync_with -> { raise CalendarSyncJob::FeedError, "The calendar link returned an error (404)." }

    assert_equal "The calendar link returned an error (404).", @source.last_sync_error
    assert_in_delta Time.current, @source.last_sync_attempted_at, 1
    assert_in_delta 1.day.ago, @source.last_synced_at, 1, "last successful sync is unchanged"
  end

  test "a link that isn't a calendar is reported too" do
    sync_with "<html>not a calendar</html>"
    assert_equal "That link didn't return a calendar.", @source.last_sync_error
  end

  test "the scheduled sync runs every few hours and queues every linked calendar" do
    assert_equal "0 */3 * * *", YAML.load_file(Rails.root.join("config/schedule.yml")).dig("sync_all_calendars", "cron")

    SyncAllCalendarsJob.perform_now
    assert_enqueued_with(job: CalendarSyncJob, args: [ @source.id ])
  end
end
