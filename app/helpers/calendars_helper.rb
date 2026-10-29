module CalendarsHelper
  # Returns Tailwind classes for an event chip based on its calendar source color
  def event_chip_classes(event)
    colors = event.calendar_source.color_classes
    "#{colors[:bg]} #{colors[:ring]} #{colors[:text]}"
  end

  # The "when" line on an event's hover tooltip (calendars/_event_tooltip):
  # "Tue, Nov 3 · 9:15–10:00 am", "Tue, Nov 3 · All day", or a range for
  # events over several days. All-day events from feeds end at midnight the
  # next day, so that end counts as the day before.
  def event_tooltip_when(event)
    starts = event.starts_at.in_time_zone
    ends   = event.ends_at.in_time_zone
    last_day = event.all_day? && ends == ends.beginning_of_day && ends > starts ? ends.to_date - 1 : ends.to_date

    if last_day <= starts.to_date
      "#{starts.strftime('%a, %b %-d')} · #{event.time_range}"
    elsif event.all_day?
      "#{starts.strftime('%a, %b %-d')} – #{last_day.strftime('%a, %b %-d')}"
    else
      day_and_time = ->(time) { "#{time.strftime('%a, %b %-d, %-I:%M')} #{time.strftime('%p').downcase}" }
      "#{day_and_time.(starts)} – #{day_and_time.(ends)}"
    end
  end

  # Navigation helpers
  def prev_month_path(date)
    d = date - 1.month
    month_calendars_path(year: d.year, month: d.month)
  end

  def next_month_path(date)
    d = date + 1.month
    month_calendars_path(year: d.year, month: d.month)
  end

  # The week the month view's Print button prints: this week while looking at
  # the current month, otherwise the month's first week.
  def calendar_print_week(month_start)
    today = Time.zone.today
    today.beginning_of_month == month_start.beginning_of_month ? today.beginning_of_week : month_start.beginning_of_week
  end

  def prev_week_path(date)
    week_calendars_path(date: (date - 1.week).to_s)
  end

  def next_week_path(date)
    week_calendars_path(date: (date + 1.week).to_s)
  end

  def prev_day_path(date)
    day_calendars_path(date: (date - 1.day).to_s)
  end

  def next_day_path(date)
    day_calendars_path(date: (date + 1.day).to_s)
  end

  def today_active?(view, date)
    case view
    when :month then Time.zone.today.between?(date.beginning_of_month, date.end_of_month)
    when :week  then Time.zone.today.between?(date, date + 6.days)
    when :day   then date == Time.zone.today
    end
  end

  def hour_label(hour)
    Time.zone.now.change(hour: hour).strftime("%-I %p").downcase
  end

  # Position an event chip within the week/day column grid.
  # Returns a style string with top % and height %.
  def event_position_style(event, hour_height_rem: 3.5, start_hour: 0, end_hour: 24)
    local_start = event.starts_at.in_time_zone(Time.zone)
    local_end   = event.ends_at.in_time_zone(Time.zone)

    start_minutes = local_start.hour * 60 + local_start.min
    end_minutes   = local_end.hour   * 60 + local_end.min

    # Event ends midnight next day — treat as end of day
    end_minutes = 24 * 60 if end_minutes == 0 && local_end.to_date > local_start.to_date

    # Minimum 15-minute visual height so short events are clickable
    end_minutes = [end_minutes, start_minutes + 15].max

    window_start = start_hour * 60
    window_end   = end_hour * 60

    # No overlap with the visible window
    return nil if end_minutes <= window_start || start_minutes >= window_end

    start_minutes = start_minutes.clamp(window_start, window_end)
    end_minutes   = end_minutes.clamp(window_start, window_end)

    top    = (start_minutes - window_start) * hour_height_rem / 60.0
    height = (end_minutes - start_minutes) * hour_height_rem / 60.0

    "top: #{top.round(4)}rem; height: #{height.round(4)}rem;"
  end
end