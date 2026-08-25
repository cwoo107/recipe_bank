class CreateWeeklyPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :weekly_plans do |t|
      t.references :household, null: false, foreign_key: true
      t.date :week_start, null: false # Monday, matches Date.current.beginning_of_week elsewhere

      t.timestamps
    end

    add_index :weekly_plans, [ :household_id, :week_start ], unique: true
  end
end
