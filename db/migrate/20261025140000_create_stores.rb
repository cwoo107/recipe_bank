class CreateStores < ActiveRecord::Migration[8.1]
  class MigrationRestockItem < ActiveRecord::Base
    self.table_name = "restock_items"
  end

  class MigrationStore < ActiveRecord::Base
    self.table_name = "stores"
  end

  class MigrationRestockItemStore < ActiveRecord::Base
    self.table_name = "restock_item_stores"
  end

  def up
    # A household's own list of the stores it shops at.
    create_table :stores do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :stores, [ :household_id, :name ], unique: true

    # The stores a restock item is bought at — any number of them.
    create_table :restock_item_stores do |t|
      t.references :restock_item, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.timestamps
    end
    add_index :restock_item_stores, [ :restock_item_id, :store_id ], unique: true

    # Carry each item's typed-in store over to the household's list, one
    # store per name however it was capitalized or spaced. The old column is
    # left in place, unused.
    MigrationRestockItem.where.not(store: [ nil, "" ]).find_each do |item|
      name = item.store.strip
      next if name.empty?

      store = MigrationStore.where(household_id: item.household_id).where("LOWER(name) = ?", name.downcase).first ||
              MigrationStore.create!(household_id: item.household_id, name: name)
      MigrationRestockItemStore.find_or_create_by!(restock_item_id: item.id, store_id: store.id)
    end
  end

  def down
    drop_table :restock_item_stores
    drop_table :stores
  end
end
