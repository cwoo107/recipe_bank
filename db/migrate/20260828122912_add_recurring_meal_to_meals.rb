class AddRecurringMealToMeals < ActiveRecord::Migration[8.1]
  def change
    add_reference :meals, :recurring_meal, null: true, foreign_key: true
  end
end
