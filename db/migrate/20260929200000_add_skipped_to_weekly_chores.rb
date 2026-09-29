# A weekly/biweekly chore taken off one week ("just this week") keeps its row
# for that week, marked skipped, so auto-scheduling doesn't put it straight
# back — see WeeklyChore#skip!.
class AddSkippedToWeeklyChores < ActiveRecord::Migration[8.1]
  def change
    add_column :weekly_chores, :skipped, :boolean, default: false, null: false
  end
end
