module Dashboard
  class CalendarSection < Section
    KEY   = "calendar".freeze
    LABEL = "Calendar".freeze
    ICON  = "calendar".freeze

    def connected?
      household.calendar_sources.exists?
    end

    def reviewed?
      weekly_plan_section.done?
    end

    def events_count
      household.calendar_events.visible.in_range(week_start.beginning_of_day, (week_start + 7).beginning_of_day).count
    end

    # The week's events for the week grid on the planner's calendar step
    # (calendars/_week_grid) — loaded the way the Calendar's Week view does.
    def week_end = week_start + 6

    def week_events
      @week_events ||= household.calendar_events.visible.in_range(week_start, week_end + 1.day)
                                .includes(:calendar_source).chronological.to_a
    end

    def events_by_day  = CalendarEvent.group_by_start_day(week_events, week_start, week_end)
    def all_day_events = week_events.select(&:all_day?)

    # Two distinct empty states: no calendar connected at all, vs. connected
    # but this week hasn't been marked reviewed yet.
    def empty?
      !connected? || !reviewed?
    end

    def summary_line
      "#{events_count} event#{'s' unless events_count == 1} #{week_phrase} — reviewed"
    end

    def empty_headline
      "Calendar"
    end

    def empty_body
      if connected?
        "#{events_count} event#{'s' unless events_count == 1} #{week_phrase} — not yet reviewed."
      else
        "No calendar connected yet."
      end
    end

    def cta_label
      connected? ? "Review calendar" : "Connect a calendar"
    end

    def page_path = week_calendars_path(date: week_start)
  end
end
