# Who a recurring meal is for — copied onto each meal the rule generates.
class RecurringMealAssignment < ApplicationRecord
  belongs_to :recurring_meal
  belongs_to :household_member

  validates :household_member_id, uniqueness: { scope: :recurring_meal_id }
  validate :member_in_rule_household

  private

  def member_in_rule_household
    return if recurring_meal.nil? || household_member.nil?

    errors.add(:household_member, "must be in this household") unless household_member.household_id == recurring_meal.household_id
  end
end
