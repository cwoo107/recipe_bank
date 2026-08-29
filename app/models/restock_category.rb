class RestockCategory < ApplicationRecord
  belongs_to :household
  has_many :restock_items, dependent: :destroy

  acts_as_list scope: :household_id

  # Seeded onto every household when it's created (see Household#seed_default_restock_categories).
  # Misc Supplies is deliberately not one of these — that slot in the board is
  # instead the "Add a restock category" tile.
  DEFAULT_NAMES = [ "Bathrooms", "Laundry Room", "Kitchen", "Pantry", "Refrigerator/Freezer" ].freeze

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }

  scope :ordered, -> { order(:position) }
end
