# Daily chores: one weekly_chores row per day instead of one per week, so
# the one-row-per-chore-per-week index widens to include the day (the
# one-per-week rule for every other frequency stays as a model validation).
# daily_since is the first day a daily chore goes on the board, so turning a
# chore daily mid-week doesn't back-fill the days already past.
class AddDailyFrequencyToChores < ActiveRecord::Migration[8.1]
  def change
    add_column :chores, :daily_since, :date

    remove_index :weekly_chores, [ :chore_id, :week_start ], unique: true
    add_index :weekly_chores, [ :chore_id, :week_start, :scheduled_date ], unique: true,
              name: "index_weekly_chores_on_chore_week_and_date"
  end
end
