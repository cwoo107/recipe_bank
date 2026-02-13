class AddServingsToRecipe < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :servings, :integer
  end
end
