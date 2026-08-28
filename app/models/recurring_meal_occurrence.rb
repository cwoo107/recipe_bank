class RecurringMealOccurrence < ApplicationRecord
  belongs_to :recurring_meal
  belongs_to :meal, optional: true

  validates :date, presence: true
  validates :date, uniqueness: { scope: :recurring_meal_id }
end
