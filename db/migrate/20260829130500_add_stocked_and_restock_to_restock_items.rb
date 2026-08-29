class AddStockedAndRestockToRestockItems < ActiveRecord::Migration[8.1]
  def change
    add_column :restock_items, :stocked,                     :boolean,  null: false, default: false
    add_column :restock_items, :restock,                      :boolean,  null: false, default: false
    add_column :restock_items, :last_date_checked_stocked,    :datetime
    add_column :restock_items, :last_date_checked_restocked,  :datetime
  end
end
