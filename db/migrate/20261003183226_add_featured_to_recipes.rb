class AddFeaturedToRecipes < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :featured, :boolean
  end
end
