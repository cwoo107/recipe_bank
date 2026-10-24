class ChoreCategory < ApplicationRecord
  belongs_to :household
  # Deleting a category leaves its chores in place — they fall back to the
  # board's "Uncategorized" row rather than disappearing with it.
  has_many :chores, dependent: :nullify

  acts_as_list scope: :household_id

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }

  scope :ordered, -> { order(:position) }
end
