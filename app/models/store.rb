# A store the household shops at — "Costco", "Target". Restock items are
# sorted into any number of them, and the restock shopping list groups by them.
class Store < ApplicationRecord
  belongs_to :household

  has_many :restock_item_stores, dependent: :destroy
  has_many :restock_items, through: :restock_item_stores

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }

  before_validation { self.name = name.to_s.strip }

  scope :ordered, -> { order(Arel.sql("LOWER(stores.name)")) }
end
