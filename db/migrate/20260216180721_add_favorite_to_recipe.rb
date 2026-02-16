class AddFavoriteToRecipe < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :favorite, :boolean
  end
end
