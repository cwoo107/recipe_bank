class ChangeQuantityToFloatInRecipeIngredients < ActiveRecord::Migration[8.1]
  def up
    change_column :recipe_ingredients, :quantity, :float
  end

  def down
    change_column :recipe_ingredients, :quantity, :boolean
  end
end