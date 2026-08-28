class AddPlanningTimestampsToWeeklyPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :weekly_plans, :planning_started_at, :datetime
    add_column :weekly_plans, :planning_completed_at, :datetime
  end
end
