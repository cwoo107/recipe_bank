# Which grocery ingredients are the same thing as a restock item ("Olive oil"
# on the list from a recipe, "Olive oil" on the restock checklist). Saved once
# the user answers the "also on your restock list?" review after generating
# the list — a no as well as a yes, so the same pair isn't asked about again.
class CreateRestockItemIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :restock_item_ingredients do |t|
      t.references :restock_item, null: false, foreign_key: true
      t.references :ingredient, null: false, foreign_key: true
      t.boolean :linked, null: false, default: true
      t.timestamps
    end
    add_index :restock_item_ingredients, %i[restock_item_id ingredient_id], unique: true
  end
end
