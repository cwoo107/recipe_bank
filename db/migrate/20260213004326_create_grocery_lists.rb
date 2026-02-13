class CreateGroceryLists < ActiveRecord::Migration[8.1]
  def change
    create_table :grocery_lists do |t|
      t.date :week_of
      t.references :ingredient, null: false, foreign_key: true
      t.references :meal, null: false, foreign_key: true
      t.integer :units
      t.boolean :checked
      t.boolean :manually_adjusted

      t.timestamps
    end
  end
end
