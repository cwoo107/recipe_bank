class AddScheduledDateToWeeklyChores < ActiveRecord::Migration[8.1]
  def change
    add_column :weekly_chores, :scheduled_date, :date

    add_index :weekly_chores, [ :household_id, :week_start, :scheduled_date ]
  end
end
