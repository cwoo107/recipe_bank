class RestockCategory < ApplicationRecord
  belongs_to :household
  has_many :restock_items, dependent: :destroy

  acts_as_list scope: :household_id

  # Seeded onto every household when it's created (see Household#seed_default_restock_categories).
  # Misc Supplies is deliberately not one of these — that slot in the board is
  # instead the "Add a restock category" tile. Each comes with a few starter
  # items so the board isn't empty on day one.
  DEFAULTS = {
    "Bathrooms"            => [ "Toilet Paper", "Hand Soap", "Toothpaste" ],
    "Laundry Room"         => [ "Laundry Detergent", "Dryer Sheets" ],
    "Kitchen"              => [ "Dish Soap", "Paper Towels", "Trash Bags" ],
    "Pantry"               => [ "Olive Oil", "Salt", "Rice" ],
    "Refrigerator/Freezer" => [ "Milk", "Eggs", "Butter" ]
  }.freeze
  DEFAULT_NAMES = DEFAULTS.keys.freeze

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }

  scope :ordered, -> { order(:position) }
end
