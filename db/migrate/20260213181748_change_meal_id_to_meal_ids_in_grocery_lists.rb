class ChangeMealIdToMealIdsInGroceryLists < ActiveRecord::Migration[8.1]
  def change
    remove_column :grocery_lists, :meal_id
    add_column :grocery_lists, :meal_ids, :text
  end
end
