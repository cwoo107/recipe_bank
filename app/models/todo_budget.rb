# A household's to-do time for one week: what they've set aside
# (Household#todo_minutes_budget) against what's planned into it — everything
# still to do that week plus the time what's been completed took. Feeds the
# time meter (todos/_budget) and the Gantt (todos/_gantt).
class TodoBudget
  # At this share of the time set aside, the meter turns from green to yellow.
  CLOSE_AT = 0.8

  attr_reader :household, :week_start

  def initialize(household, week_start = Todo.current_week_start(household))
    @household  = household
    @week_start = week_start
  end

  # Completed first (they've already used their time), then what's left in
  # the This Week column's order.
  def todos
    @todos ||= Todo.done_for_week(household, week_start).includes(:tags).to_a +
               Todo.open_for_week(household, week_start).includes(:tags).to_a
  end

  def budget_minutes    = household.todo_minutes_budget
  def planned_minutes   = @planned_minutes ||= todos.sum(&:minutes_for_week)
  def remaining_minutes = budget_minutes - planned_minutes

  def state
    if planned_minutes > budget_minutes then :over
    elsif planned_minutes >= budget_minutes * CLOSE_AT then :close
    else :plenty
    end
  end

  # How full the week is, 0–100 (capped — the message says by how much it's over).
  def percent
    return 100 unless budget_minutes.positive?
    [ (planned_minutes * 100.0 / budget_minutes).round, 100 ].min
  end

  def message
    set_aside = Todo.humanize_duration(budget_minutes)
    planned   = Todo.humanize_duration(planned_minutes)
    case state
    when :over
      "You've set aside #{set_aside} for to-dos, but you have planned #{planned}."
    when :close
      "You've planned #{planned} of the #{set_aside} you've set aside for to-dos — only #{Todo.humanize_duration(remaining_minutes)} left."
    else
      "You've planned #{planned} of the #{set_aside} you've set aside for to-dos."
    end
  end

  # ── Gantt data (consumed by gantt_controller.js) ──────────────────────
  #
  # The week's time as one run of hours, 0 to the time set aside (or further,
  # when more is planned). Each to-do takes up its own block of hours, one
  # after another in order, so the chart shows how far into the week's time
  # the plan reaches.
  def gantt_data
    cursor = 0
    rows = todos.map do |todo|
      minutes = todo.minutes_for_week
      start   = cursor
      cursor += minutes
      {
        id:          todo.id,
        title:       todo.title,
        start:       hours(start),
        end:         hours(cursor),
        color:       todo.gantt_color,
        status:      todo.status,
        over:        cursor > budget_minutes,
        range_label: minutes.positive? ? "#{clock(start)} → #{clock(cursor)}" : "No estimate",
        meta:        todo.status == "done" ? "Completed · #{todo.actual_hm}" : "#{todo.priority_label} · #{todo.estimated_hm}"
      }
    end

    {
      week_label:   week_label,
      budget_hours: hours(budget_minutes),
      max_hours:    hours([ budget_minutes, cursor ].max),
      rows:         rows
    }
  end

  def week_label
    "#{week_start.strftime('%b %-d')} – #{(week_start + 6).strftime('%b %-d')}"
  end

  private

  def hours(minutes) = (minutes / 60.0).round(3)

  # A point in the week's hours: "0h", "1h 30m".
  def clock(minutes) = minutes.zero? ? "0h" : Todo.humanize_minutes(minutes)
end
