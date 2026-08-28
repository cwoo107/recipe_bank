class AddDefaultWeekdayStartedOnToChores < ActiveRecord::Migration[8.1]
  def change
    # The week_start of the week a chore was first (or most recently)
    # scheduled onto its current default_weekday — the anchor biweekly
    # chores count from to know which weeks to skip.
    add_column :chores, :default_weekday_started_on, :date
  end
end
