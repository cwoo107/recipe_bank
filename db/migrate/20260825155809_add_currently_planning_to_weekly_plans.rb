class AddCurrentlyPlanningToWeeklyPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :weekly_plans, :currently_planning, :boolean, null: false, default: false
  end
end
