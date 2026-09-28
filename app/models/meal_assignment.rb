# "Who's eating this meal" — optional. A meal with no assignments is shared
# by the whole family (see Meal#share_for).
class MealAssignment < ApplicationRecord
  belongs_to :meal
  belongs_to :household_member

  validates :household_member_id, uniqueness: { scope: :meal_id }
  validate :member_in_meal_household

  private

  def member_in_meal_household
    return if meal.nil? || household_member.nil?

    errors.add(:household_member, "must be in this household") unless household_member.household_id == meal.household_id
  end
end
