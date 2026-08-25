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

    # Two distinct empty states: no calendar connected at all, vs. connected
    # but this week hasn't been marked reviewed yet.
    def empty?
      !connected? || !reviewed?
    end

    def summary_line
      "#{events_count} event#{'s' unless events_count == 1} this week — reviewed"
    end

    def empty_headline
      "Calendar"
    end

    def empty_body
      if connected?
        "#{events_count} event#{'s' unless events_count == 1} this week — not yet reviewed."
      else
        "No calendar connected yet."
      end
    end

    def cta_label
      connected? ? "Review calendar" : "Connect a calendar"
    end
  end
end
