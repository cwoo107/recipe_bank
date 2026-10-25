class WeeklyTodoPlanning < ActiveRecord::Migration[8.1]
  def up
    # How the household budgets time for to-dos: "week" (todo_minutes_per_week)
    # or "day" (the existing minutes_per_day, times seven).
    add_column :households, :todo_time_period, :string, default: "week", null: false
    add_column :households, :todo_minutes_per_week, :integer, default: 420, null: false
    # Carry each household's daily figure over as its weekly one.
    execute "UPDATE households SET todo_minutes_per_week = minutes_per_day * 7"

    # The week (its first day) a to-do was put into "To-Do This Week" for.
    add_column :todos, :planned_week, :date
    add_index :todos, [ :household_id, :status, :planned_week ]

    create_table :todo_tags do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false
      t.timestamps
    end
    add_index :todo_tags, [ :household_id, :name ], unique: true

    create_table :todo_taggings do |t|
      t.references :todo, null: false, foreign_key: true
      t.references :todo_tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :todo_taggings, [ :todo_id, :todo_tag_id ], unique: true
  end

  def down
    drop_table :todo_taggings
    drop_table :todo_tags
    remove_index :todos, [ :household_id, :status, :planned_week ]
    remove_column :todos, :planned_week
    remove_column :households, :todo_minutes_per_week
    remove_column :households, :todo_time_period
  end
end
