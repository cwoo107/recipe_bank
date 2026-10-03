# A meal can be a note instead of a recipe — "Dinner at the Hendersons'",
# "Takeout" — so it holds the slot without anything to cook.
class AddNoteToMeals < ActiveRecord::Migration[8.1]
  def change
    add_column :meals, :note, :string
    change_column_null :meals, :recipe_id, true
  end
end
