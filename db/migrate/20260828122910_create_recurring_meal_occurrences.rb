class CreateRecurringMealOccurrences < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_meal_occurrences do |t|
      t.references :recurring_meal, null: false, foreign_key: true
      t.references :meal, null: true, foreign_key: true
      t.date :date, null: false

      t.timestamps
    end

    add_index :recurring_meal_occurrences, [:recurring_meal_id, :date], unique: true
  end
end
