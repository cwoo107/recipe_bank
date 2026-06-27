module CalendarsHelper
  # Returns Tailwind classes for an event chip based on its calendar source color
  def event_chip_classes(event)
    colors = event.calendar_source.color_classes
    "#{colors[:bg]} #{colors[:ring]} #{colors[:text]}"
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
  def event_position_style(event, hour_height_rem: 3.5)
    local_start = event.starts_at.in_time_zone(Time.zone)
    local_end   = event.ends_at.in_time_zone(Time.zone)

    start_minutes = local_start.hour * 60 + local_start.min
    end_minutes   = local_end.hour   * 60 + local_end.min

    # Event ends midnight next day — treat as end of day
    end_minutes = 24 * 60 if end_minutes == 0 && local_end.to_date > local_start.to_date

    # Minimum 15-minute visual height so short events are clickable
    end_minutes = [end_minutes, start_minutes + 15].max

    top    = start_minutes * hour_height_rem / 60.0
    height = (end_minutes - start_minutes) * hour_height_rem / 60.0

    "top: #{top.round(4)}rem; height: #{height.round(4)}rem;"
  end
end