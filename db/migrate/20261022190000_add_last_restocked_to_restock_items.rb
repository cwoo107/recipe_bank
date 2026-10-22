# When a restock item was last restocked — set when Restock is selected
# (RestockItem#mark_restock!), and editable in its form.
class AddLastRestockedToRestockItems < ActiveRecord::Migration[8.1]
  def change
    add_column :restock_items, :last_restocked, :date
  end
end
