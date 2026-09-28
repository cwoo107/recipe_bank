class AddCompactMealsViewToUsers < ActiveRecord::Migration[8.1]
  def change
    # Per-user display preference — hides ingredient/serving/nutrition/cost
    # lines on meal cards so the weekly meal plan fits on one screen.
    add_column :users, :compact_meals_view, :boolean, default: false, null: false
  end
end
