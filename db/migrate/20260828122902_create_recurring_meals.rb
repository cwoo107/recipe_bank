class CreateRecurringMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_meals do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.string :meal_name, null: false
      t.integer :servings
      t.string :pattern_type, null: false, default: "interval"
      t.integer :interval_days
      t.text :days_of_week
      t.date :start_date, null: false
      t.date :end_date

      t.timestamps
    end
  end
end
