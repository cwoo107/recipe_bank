module Dashboard
  # Planning to-dos for the week: settle what's left over from earlier weeks
  # (finished, or carried into this one), pick what goes into this week from
  # the To-Do column, and keep it all within the time set aside for to-dos
  # (TodoBudget). "Open" = still to do in the week; "done" = completed in it.
  class TodosSection < Section
    KEY   = "todos".freeze
    LABEL = "To-dos".freeze
    ICON  = "todos".freeze

    def budget
      @budget ||= TodoBudget.new(household, week_start)
    end

    def open_this_week
      @open_this_week ||= Todo.open_for_week(household, week_start)
    end

    def done_this_week
      @done_this_week ||= household.todos.ended_in_week(week_start)
    end

    # Left in "To-Do This Week" from a week before the one being planned.
    def carried_over
      @carried_over ||= Todo.carried_over(household, week_start).includes(:assignee, :tags).to_a
    end

    # Planned for exactly this week (carried-over ones are listed apart),
    # in the order they'll be worked through.
    def planned
      @planned ||= household.todos.where(status: "in_progress", planned_week: week_start)
                            .ordered.includes(:assignee, :tags).to_a
    end

    # The To-Do column, to pick from.
    def backlog
      @backlog ||= household.todos.by_status("todo").includes(:assignee, :tags).to_a
    end

    def open_count = open_this_week.count
    def done_count = done_this_week.count

    def empty?
      open_count.zero? && done_count.zero?
    end

    def summary_line
      "#{open_count} open, #{done_count} done #{week_phrase}"
    end

    def detail_line
      "#{Todo.humanize_duration(budget.planned_minutes)} of #{Todo.humanize_duration(budget.budget_minutes)} planned"
    end

    def empty_headline = "To-dos"
    def empty_body     = "Nothing planned for #{week_phrase} yet."
    def cta_label      = "Plan to-dos"

    def page_path = todos_path
  end
end
