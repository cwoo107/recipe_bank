class AddServingsToMeals < ActiveRecord::Migration[8.1]
  def change
    add_column :meals, :servings, :integer
  end
end
