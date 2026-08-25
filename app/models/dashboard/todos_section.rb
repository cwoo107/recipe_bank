module Dashboard
  # "Planning to-dos for the week" is triage of what's already scheduled into
  # this week — not creating new tasks. "Open" = in_progress todos whose
  # scheduled window overlaps this week; "done" = todos completed this week.
  class TodosSection < Section
    KEY   = "todos".freeze
    LABEL = "To-dos".freeze
    ICON  = "todos".freeze

    def open_this_week
      @open_this_week ||= household.todos
                                    .where(status: "in_progress")
                                    .where.not(start_date: nil, end_date: nil)
                                    .where("start_date < ? AND end_date >= ?", week_start + 7, week_start)
    end

    def done_this_week
      @done_this_week ||= household.todos.ended_this_week
    end

    def open_count = open_this_week.count
    def done_count = done_this_week.count

    def empty?
      open_count.zero? && done_count.zero?
    end

    def summary_line
      "#{open_count} open, #{done_count} done this week"
    end

    def empty_headline = "To-dos"
    def empty_body     = "Nothing scheduled into this week yet."
    def cta_label      = "Review to-dos"
  end
end
