class AddSourceRecipeToRecipes < ActiveRecord::Migration[8.1]
  def change
    # Set when a recipe is saved out of the public browse list — lets us show
    # "already saved" instead of offering the same copy twice.
    add_reference :recipes, :source_recipe, null: true, foreign_key: { to_table: :recipes }
  end
end
