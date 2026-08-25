class CreateWeeklyPlanSections < ActiveRecord::Migration[8.1]
  def change
    create_table :weekly_plan_sections do |t|
      t.references :weekly_plan, null: false, foreign_key: true
      t.string :key, null: false
      t.string :status, null: false, default: "not_started" # not_started | in_progress | skipped | done
      t.references :updated_by, foreign_key: { to_table: :users }
      t.datetime :status_changed_at

      t.timestamps
    end

    add_index :weekly_plan_sections, [ :weekly_plan_id, :key ], unique: true
  end
end
