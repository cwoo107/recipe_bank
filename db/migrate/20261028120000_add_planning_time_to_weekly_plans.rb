# How long each week took to plan (WeeklyPlan#track_planning_time!) — the
# active time across every session, not one start/finish pair, so it survives
# resuming and leaves out time spent away.
class AddPlanningTimeToWeeklyPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :weekly_plans, :planning_seconds, :integer, default: 0, null: false
    add_column :weekly_plans, :planning_last_active_at, :datetime
  end
end
