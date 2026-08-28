class CreateWeeklyChores < ActiveRecord::Migration[8.1]
  def change
    create_table :weekly_chores do |t|
      t.references :household, null: false, foreign_key: true
      t.references :chore, null: false, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :household_members }
      t.date :week_start, null: false
      t.boolean :completed, null: false, default: false
      t.datetime :completed_at
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :weekly_chores, [ :household_id, :week_start ]
    add_index :weekly_chores, [ :chore_id, :week_start ], unique: true
  end
end
