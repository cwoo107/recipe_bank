require "net/http"
require "uri"

# CalendarSyncJob fetches and upserts events for a single CalendarSource.
#
# Gem requirements:
#   gem 'icalendar'   # parse .ics feeds (covers iCal, Apple, Google public calendars)
#
# For Google / Outlook OAuth sync, see the stubbed methods at the bottom.
# Both providers also expose an iCal/ICS export URL which is the easiest path.

class CalendarSyncJob < ApplicationJob
  queue_as :default

  SYNC_WINDOW_PAST   = 3.months
  SYNC_WINDOW_FUTURE = 12.months

  def perform(source_id)
    source = CalendarSource.find_by(id: source_id)
    return unless source

    if source.ical_url.present?
      sync_ical(source)
    else
      case source.provider
      when "google"
        sync_google(source)
      when "outlook"
        sync_outlook(source)
      end
    end

    source.update!(last_synced_at: Time.current, synced: true)
  rescue => e
    Rails.logger.error "[CalendarSyncJob] source=#{source_id} error=#{e.message}"
    raise
  end

  private

  # ──────────────────────────────────────────────────────────────
  # iCal / WebCal (covers Apple Calendar exports too)
  # ──────────────────────────────────────────────────────────────
  def sync_ical(source)
    return unless source.ical_url.present?

    body = fetch_url(source.ical_url)
    return unless body

    begin
      require "icalendar"
      require "icalendar/tzinfo"
    rescue LoadError
      Rails.logger.error "[CalendarSyncJob] Add `gem 'icalendar'` to your Gemfile to enable iCal sync."
      return
    end

    calendars = Icalendar::Calendar.parse(body)
    window_start = SYNC_WINDOW_PAST.ago
    window_end   = SYNC_WINDOW_FUTURE.from_now

    upserted_uids = []

    calendars.each do |cal|
      # Resolve the calendar's timezone for floating-time events
      cal_tz = resolve_tz(cal)

      cal.events.each do |vevent|
        uid = vevent.uid.to_s.strip
        next if uid.blank?

        starts_at, all_day = parse_dt(vevent.dtstart, cal_tz)
        ends_at,   _       = parse_dt(vevent.dtend || vevent.dtstart, cal_tz)

        if all_day
          ends_at = ends_at > starts_at ? ends_at - 1.second : starts_at.end_of_day
        end

        next if ends_at < window_start || starts_at > window_end

        # Collect the UID regardless of whether save succeeds
        upserted_uids << uid

        attrs = {
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
          recurrence_rule: vevent.rrule.first&.to_s.presence
        }

        event = CalendarEvent.find_or_initialize_by(
          calendar_source_id: source.id,
          external_uid:       uid
        )
        event.assign_attributes(attrs)
        event.save! if event.new_record? || event.changed?
      rescue => e
        Rails.logger.warn "[CalendarSyncJob] Skipping event uid=#{uid} error=#{e.message}"
      end
    end

    # Remove events that disappeared from the feed (within our window)
    CalendarEvent.where(calendar_source_id: source.id)
                 .where.not(external_uid: upserted_uids)
                 .where(external_uid: CalendarEvent.where(calendar_source_id: source.id)
                                                   .where("starts_at >= ?", window_start)
                                                   .select(:external_uid))
                 .destroy_all
  end

  # ──────────────────────────────────────────────────────────────
  # Google Calendar (OAuth)
  # ──────────────────────────────────────────────────────────────
  # Requires: gem 'google-apis-calendar_v3'
  #
  # Easiest alternative: have the user paste their Google Calendar's
  # public iCal URL (Settings → [calendar] → "Secret address in iCal format")
  # and treat it as a normal ical source.
  # ──────────────────────────────────────────────────────────────
  def sync_google(source)
    # Refresh token if expired
    if source.token_expired? && source.refresh_token.present?
      refresh_google_token(source)
    end

    # TODO: implement with google-apis-calendar_v3 gem
    # Example skeleton:
    #
    #   require "google/apis/calendar_v3"
    #   svc = Google::Apis::CalendarV3::CalendarService.new
    #   svc.authorization = google_credentials(source)
    #
    #   result = svc.list_events(
    #     source.external_id || "primary",
    #     single_events: true,
    #     time_min:      SYNC_WINDOW_PAST.ago.iso8601,
    #     time_max:      SYNC_WINDOW_FUTURE.from_now.iso8601,
    #     max_results:   2500
    #   )
    #
    #   result.items.each do |item|
    #     upsert_google_event(source, item)
    #   end
    Rails.logger.info "[CalendarSyncJob] Google OAuth sync not yet implemented for source #{source.id}. Consider using the iCal export URL instead."
  end

  # ──────────────────────────────────────────────────────────────
  # Outlook / Microsoft 365 (OAuth via Microsoft Graph)
  # ──────────────────────────────────────────────────────────────
  # Requires: gem 'microsoft_graph' or plain HTTParty calls
  # Outlook also exposes an iCal URL: Settings → View all Outlook settings
  # → Calendar → Shared calendars → Publish a calendar → ICS link
  # ──────────────────────────────────────────────────────────────
  def sync_outlook(source)
    if source.token_expired? && source.refresh_token.present?
      refresh_outlook_token(source)
    end

    # TODO: implement with Microsoft Graph API
    # GET https://graph.microsoft.com/v1.0/me/calendarView
    # Authorization: Bearer {source.access_token}
    Rails.logger.info "[CalendarSyncJob] Outlook OAuth sync not yet implemented for source #{source.id}. Consider using the iCal export URL instead."
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  def fetch_url(url)
    uri = URI.parse(url.sub(/\Awebcal:\/\//i, "https://"))
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
      http.get(uri.request_uri, "User-Agent" => "RecipeBank-CalendarSync/1.0")
    end
    response.body if response.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.error "[CalendarSyncJob] fetch failed for #{url}: #{e.message}"
    nil
  end

  def parse_dt(dt, fallback_tz)
    return [Time.current, false] unless dt

    all_day = dt.is_a?(Icalendar::Values::Date)
    tz_id   = dt.respond_to?(:ical_params) && dt.ical_params["tzid"]&.first
    zone    = tz_id ? (TZInfo::Timezone.get(tz_id) rescue nil) : nil
    zone  ||= fallback_tz

    time = if all_day
             dt.to_date.to_time.in_time_zone(Time.zone)
           elsif zone
             dt.to_time.in_time_zone(zone)
           else
             dt.to_time.utc.in_time_zone(Time.zone)
           end

    [time, all_day]
  rescue
    [Time.current, false]
  end

  def resolve_tz(cal)
    tz_component = cal.timezones.first
    return Time.zone unless tz_component

    tz_id = tz_component.tzid.to_s
    TZInfo::Timezone.get(tz_id) rescue Time.zone
  rescue
    Time.zone
  end

  def map_status(ical_status)
    case ical_status.downcase
    when "tentative" then "tentative"
    when "cancelled" then "cancelled"
    else "confirmed"
    end
  end

  def refresh_google_token(source)
    # POST to https://oauth2.googleapis.com/token with refresh_token
    # Update source.access_token and source.token_expires_at
  end

  def refresh_outlook_token(source)
    # POST to https://login.microsoftonline.com/common/oauth2/v2.0/token
    # Update source.access_token and source.token_expires_at
  end
end