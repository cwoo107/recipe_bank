class AddColumnsToIngredients < ActiveRecord::Migration[8.1]
  def change
    add_column :ingredients, :unit_price, :float
    add_column :ingredients, :unit_servings, :integer
  end
end
