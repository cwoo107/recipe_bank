class RestockItemStore < ApplicationRecord
  belongs_to :restock_item
  belongs_to :store

  validates :store_id, uniqueness: { scope: :restock_item_id }
end
