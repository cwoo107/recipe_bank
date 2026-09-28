class CreateMealAssignments < ActiveRecord::Migration[8.1]
  def change
    # Optional "who's eating this" for a meal. No rows means the whole family
    # shares it.
    create_table :meal_assignments do |t|
      t.references :meal, null: false, foreign_key: true
      t.references :household_member, null: false, foreign_key: true
      t.timestamps
    end
    add_index :meal_assignments, [ :meal_id, :household_member_id ], unique: true

    # Same for recurring rules, copied onto each meal they generate.
    create_table :recurring_meal_assignments do |t|
      t.references :recurring_meal, null: false, foreign_key: true
      t.references :household_member, null: false, foreign_key: true
      t.timestamps
    end
    add_index :recurring_meal_assignments, [ :recurring_meal_id, :household_member_id ], unique: true,
              name: "index_recurring_meal_assignments_on_rule_and_member"

    add_reference :todos, :assignee, null: true, foreign_key: { to_table: :household_members }
  end
end
