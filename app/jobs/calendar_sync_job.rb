require "net/http"
require "uri"
require "icalendar"
require "icalendar/recurrence"
require "icalendar/tzinfo"

# Pulls one CalendarSource's iCal/ICS feed and brings its events in line with
# it, within SYNC_WINDOW_PAST..SYNC_WINDOW_FUTURE. Every provider works this
# way (Google's secret iCal address, Outlook's published ICS link, Apple and
# webcal feeds) — there's no account sign-in.
#
# Runs in the household's time zone, so all-day events and "floating" times
# (no zone in the feed) land on the right day.
#
# Recurring events are expanded into one CalendarEvent per occurrence, keyed
# "<UID>::<original start>" so edits to a single occurrence in the feed
# (RECURRENCE-ID) replace it, cancelled ones disappear, and EXDATEs are
# skipped. One-off events are keyed by their UID alone.
class CalendarSyncJob < ApplicationJob
  queue_as :default

  SYNC_WINDOW_PAST   = 3.months
  SYNC_WINDOW_FUTURE = 12.months

  # A feed that couldn't be fetched or read — recorded on the source and
  # shown on the calendar pages rather than retried as a crash. Messages are
  # read by the household, so they say what happened and what to do about it.
  class FeedError < StandardError; end

  FRESH_LINK = "Copy a fresh link from the calendar's sharing settings and paste it into this calendar's settings.".freeze
  NOT_A_LINK = "The calendar link isn't a web address. Paste the full link, starting with https:// or webcal://.".freeze
  RETRYING   = "This is usually temporary — it'll try again on the next automatic sync, every few hours.".freeze

  def perform(source_id)
    source = CalendarSource.find_by(id: source_id)
    return unless source&.syncable?

    Time.use_zone(source.household.zone) do
      sync(source)
      source.update!(last_synced_at: Time.current, last_sync_attempted_at: Time.current, last_sync_error: nil, synced: true)
    rescue FeedError => e
      source.update!(last_sync_attempted_at: Time.current, last_sync_error: e.message)
    ensure
      # Whoever has the calendar open sees the new events / status.
      Turbo::StreamsChannel.broadcast_refresh_to(source.household, "calendar_sources")
    end
  rescue => e
    source&.update_columns(last_sync_attempted_at: Time.current, last_sync_error: "The calendar file came back in a form that couldn't be read. Try Sync now; if it keeps happening, #{FRESH_LINK.downcase_first}")
    Rails.logger.error "[CalendarSyncJob] source=#{source_id} #{e.class}: #{e.message}"
    raise
  end

  private

  def sync(source)
    calendars = Icalendar::Calendar.parse(fetch(source.ical_url))
    raise FeedError, "That link opened a web page, not a calendar. Make sure you copied the calendar's iCal (.ics) address, not the address of the page you view it on." if calendars.empty?

    @window_start = SYNC_WINDOW_PAST.ago
    @window_end   = SYNC_WINDOW_FUTURE.from_now
    seen = []

    calendars.each do |cal|
      fallback_zone = feed_zone(cal)
      series, changed_occurrences = cal.events.partition { |vevent| vevent.recurrence_id.blank? }

      series.each do |vevent|
        occurrences(vevent, fallback_zone).each do |key, starts_at, ends_at, all_day|
          seen << key if upsert(source, vevent, key, starts_at, ends_at, all_day)
        end
      end

      # A single occurrence edited in the source calendar: replaces the one
      # the series generated (same key), or removes it if it was cancelled.
      changed_occurrences.each do |vevent|
        key = occurrence_key(vevent.uid, vevent.recurrence_id)
        if vevent.status.to_s.casecmp?("cancelled")
          seen.delete(key)
          next
        end

        starts_at, all_day = parse_time(vevent.dtstart, fallback_zone)
        ends_at, _ = parse_time(vevent.dtend || vevent.dtstart, fallback_zone)
        ends_at = all_day_end(starts_at, ends_at) if all_day
        next if ends_at < @window_start || starts_at > @window_end

        seen << key unless seen.include?(key)
        upsert(source, vevent, key, starts_at, ends_at, all_day)
      end
    end

    remove_missing(source, seen)
  end

  # [key, starts_at, ends_at, all_day] for each time this event happens in
  # the window.
  def occurrences(vevent, fallback_zone)
    uid = vevent.uid.to_s.strip
    return [] if uid.blank?

    starts_at, all_day = parse_time(vevent.dtstart, fallback_zone)
    ends_at, _ = parse_time(vevent.dtend || vevent.dtstart, fallback_zone)
    ends_at = all_day_end(starts_at, ends_at) if all_day

    if vevent.rrule.blank?
      return [] if ends_at < @window_start || starts_at > @window_end
      return [ [ uid, starts_at, ends_at, all_day ] ]
    end

    duration = ends_at - starts_at
    vevent.occurrences_between(@window_start - duration, @window_end).map do |occurrence|
      if all_day
        # The gem hands back all-day dates as the server's local midnight —
        # keep just the date and anchor it to the household's zone.
        date = occurrence.start_time.getlocal.to_date
        occurrence_start = date.in_time_zone
        [ occurrence_key(uid, date), occurrence_start, occurrence_start + duration, true ]
      else
        occurrence_start = occurrence.start_time.in_time_zone
        [ occurrence_key(uid, occurrence.start_time), occurrence_start, occurrence_start + duration, false ]
      end
    end
  end

  def occurrence_key(uid, original_start)
    stamp = original_start.is_a?(Date) && !original_start.is_a?(DateTime) ? original_start.iso8601 : original_start.to_time.utc.iso8601
    "#{uid.to_s.strip}::#{stamp}"
  end

  def upsert(source, vevent, key, starts_at, ends_at, all_day)
    event = CalendarEvent.find_or_initialize_by(calendar_source_id: source.id, external_uid: key)
    event.assign_attributes(
      user_id:         source.user_id,
      household_id:    source.household_id,
      title:           vevent.summary.to_s.strip.presence || "(No title)",
      description:     vevent.description.to_s.strip.presence,
      location:        vevent.location.to_s.strip.presence,
      starts_at:       starts_at,
      ends_at:         ends_at,
      all_day:         all_day,
      status:          map_status(vevent.status.to_s),
      url:             vevent.url.to_s.strip.presence,
      recurrence_rule: vevent.rrule.first&.value_ical
    )
    event.save! if event.new_record? || event.changed?
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "[CalendarSyncJob] Skipping #{key}: #{e.message}"
    false
  end

  # Anything in the window that's no longer in the feed was deleted (or moved
  # out of range) in the source calendar. Events added in the app have no
  # external_uid and are never touched.
  def remove_missing(source, seen)
    CalendarEvent.where(calendar_source_id: source.id)
                 .where.not(external_uid: nil)
                 .where.not(external_uid: seen)
                 .where("ends_at >= ?", @window_start)
                 .destroy_all
  end

  # The feed link is whatever the user pasted, so it goes through
  # SafeUrlFetcher, which refuses internal addresses; its errors are
  # reworded here for a calendar.
  def fetch(url)
    body, _charset = SafeUrlFetcher.new(url.to_s.strip.sub(/\Awebcal:\/\//i, "https://"),
                                        user_agent: "HomemakersHaven-CalendarSync/1.0",
                                        accept: "text/calendar, */*",
                                        max_bytes: 20.megabytes,
                                        open_timeout: 10, read_timeout: 20).fetch
    body
  rescue SafeUrlFetcher::Error => e
    raise FeedError, fetch_error_message(e)
  end

  def fetch_error_message(error)
    case error.reason
    when :not_a_link
      NOT_A_LINK
    when :not_allowed
      "The calendar link points to an address that can't be synced from. Paste a link to a public calendar. #{FRESH_LINK}"
    when :not_found
      "The website in the calendar link couldn't be found. Check the link for typos, or #{FRESH_LINK.downcase_first}"
    when :timeout
      "The calendar took too long to respond. #{RETRYING}"
    when :refused
      "The calendar's website turned the connection away. #{RETRYING}"
    when :unreachable
      "The calendar's website couldn't be reached. #{RETRYING}"
    when :ssl
      "A secure connection to the calendar's website couldn't be made. If this keeps happening, #{FRESH_LINK.downcase_first}"
    when :too_large
      "The calendar file is too large to sync. If this keeps happening, #{FRESH_LINK.downcase_first}"
    when :http_status
      http_error_message(error.status)
    else # a redirect that went nowhere, or round in circles
      "The calendar link kept redirecting without reaching a calendar. #{FRESH_LINK}"
    end
  end

  def http_error_message(status)
    case status
    when 401, 403
      "The calendar wouldn't let us in. It may be private, or its sharing link was turned off or reset. #{FRESH_LINK}"
    when 404, 410
      "There's no calendar at that link anymore. The calendar may have been deleted, or its link was reset. #{FRESH_LINK}"
    when 429
      "The calendar's provider asked us to slow down. #{RETRYING}"
    when 500..599
      "The calendar's provider is having trouble right now. #{RETRYING}"
    else
      "The calendar's provider sent back something other than the calendar (error #{status}). Try Sync now; if it keeps happening, #{FRESH_LINK.downcase_first}"
    end
  end

  # [time, all_day?] — all-day dates become midnight in the household's zone;
  # timed values keep their own zone, else the feed's, else the household's.
  def parse_time(value, fallback_zone)
    return [ Time.current, false ] unless value

    if value.is_a?(Icalendar::Values::Date)
      [ value.to_date.in_time_zone, true ]
    else
      # Zoned values (including "Z", which parses as TZID=UTC) carry their own
      # zone; floating ones are wall-clock time in the feed's or household's.
      if value.ical_params["tzid"].present?
        [ value.to_time.in_time_zone, false ]
      else
        wall = value.value
        zone = fallback_zone || Time.zone
        [ zone.local(wall.year, wall.month, wall.day, wall.hour, wall.min, wall.sec), false ]
      end
    end
  end

  # All-day DTEND is the day after (exclusive); store the last moment of the
  # final day.
  def all_day_end(starts_at, ends_at)
    ends_at > starts_at ? ends_at - 1.second : starts_at.end_of_day
  end

  def feed_zone(cal)
    tzid = cal.timezones.first&.tzid.to_s.presence ||
           cal.custom_property("x_wr_timezone").first.to_s.presence
    tzid && ActiveSupport::TimeZone[tzid]
  end

  def map_status(ical_status)
    case ical_status.downcase
    when "tentative" then "tentative"
    when "cancelled" then "cancelled"
    else "confirmed"
    end
  end
end
