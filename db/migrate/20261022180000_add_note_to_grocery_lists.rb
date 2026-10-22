# A grocery list line can be a note instead of an ingredient — "birthday
# candles", "check if we need foil" — like a note-only meal.
class AddNoteToGroceryLists < ActiveRecord::Migration[8.1]
  def change
    add_column :grocery_lists, :note, :string
    change_column_null :grocery_lists, :ingredient_id, true
  end
end
