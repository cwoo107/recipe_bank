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
  # shown in the calendar sidebar rather than retried as a crash.
  class FeedError < StandardError; end

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
    source&.update_columns(last_sync_attempted_at: Time.current, last_sync_error: "Something went wrong reading this calendar.")
    Rails.logger.error "[CalendarSyncJob] source=#{source_id} #{e.class}: #{e.message}"
    raise
  end

  private

  def sync(source)
    calendars = Icalendar::Calendar.parse(fetch(source.ical_url))
    raise FeedError, "That link didn't return a calendar." if calendars.empty?

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

  def fetch(url)
    uri = URI.parse(url.to_s.strip.sub(/\Awebcal:\/\//i, "https://"))
    raise FeedError, "That isn't a web link." unless uri.is_a?(URI::HTTP) && uri.host.present?

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
      http.get(uri.request_uri, "User-Agent" => "HomemakersHaven-CalendarSync/1.0")
    end
    return response.body if response.is_a?(Net::HTTPSuccess)

    raise FeedError, "The calendar link returned an error (#{response.code}). It may have been reset — paste a fresh link."
  rescue URI::InvalidURIError
    raise FeedError, "That isn't a web link."
  rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout => e
    raise FeedError, "Couldn't reach the calendar (#{e.class.name.demodulize})."
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
