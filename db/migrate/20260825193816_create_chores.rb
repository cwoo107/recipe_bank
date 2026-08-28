class CreateChores < ActiveRecord::Migration[8.1]
  def change
    create_table :chores do |t|
      t.references :household, null: false, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :household_members }
      t.string :name, null: false
      t.text :description
      t.string :frequency, null: false, default: "weekly" # weekly | biweekly | monthly | quarterly | semiannually | annually
      t.datetime :last_completed_at

      t.timestamps
    end

    add_index :chores, [ :household_id, :name ]
  end
end
