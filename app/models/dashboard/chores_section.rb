module Dashboard
  class ChoresSection < Section
    KEY   = "chores".freeze
    LABEL = "Chores".freeze
    ICON  = "chores".freeze

    def chores_this_week
      @chores_this_week ||= begin
        ensure_recurring_chores_scheduled!
        household.weekly_chores.for_week(week_start).includes(:chore, :assignee)
      end
    end

    def due_chores
      @due_chores ||= begin
        ensure_recurring_chores_scheduled!
        Chore.due_and_unscheduled(household, week_start: week_start)
      end
    end

    def empty?
      chores_this_week.none?
    end

    def summary_line
      count = chores_this_week.count
      "#{count} chore#{'s' unless count == 1} on this week's list"
    end

    def detail_line
      due_chores.any? ? "#{due_chores.size} due and not yet added" : nil
    end

    def empty_headline = "Chores"
    def empty_body     = "No chores scheduled for this week yet."
    def cta_label      = "Plan chores"

    private

    def ensure_recurring_chores_scheduled!
      return if @recurring_chores_scheduled

      Chore.auto_schedule_recurring!(household, week_start: week_start)
      @recurring_chores_scheduled = true
    end
  end
end
