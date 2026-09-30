class AddOptionalToRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    add_column :recipe_ingredients, :optional, :boolean, default: false, null: false
  end
end
