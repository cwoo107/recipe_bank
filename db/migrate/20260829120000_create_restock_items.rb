class CreateRestockItems < ActiveRecord::Migration[8.1]
  def change
    create_table :restock_items do |t|
      t.string  :name,     null: false
      t.string  :brand
      t.string  :store
      t.string  :category, null: false, default: "misc_supplies" # bathrooms | laundry_room | kitchen | pantry | refrigerator_freezer | misc_supplies
      t.integer :position, null: false, default: 0
      t.integer :user_id,      null: false
      t.integer :household_id, null: false

      t.timestamps
    end

    add_index :restock_items, [ :household_id, :category ]
    add_index :restock_items, [ :household_id, :category, :position ]
    add_foreign_key :restock_items, :users
    add_foreign_key :restock_items, :households
  end
end
