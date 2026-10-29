module CalendarEventsHelper
  # Options for the event form's time selects: every 15 minutes, labelled
  # like the rest of the calendar ("9:15 am"). A time off that grid (e.g. an
  # event moved from another calendar) is added so editing doesn't change it.
  def event_time_options(selected)
    times = (0...24 * 60).step(15).map { |minutes| format("%02d:%02d", minutes / 60, minutes % 60) }
    times = (times + [ selected ]).sort if selected.present? && !times.include?(selected)

    options_for_select(times.map { |time| [ Time.zone.parse(time).strftime("%-I:%M %p").downcase, time ] }, selected)
  end
end
