module HouseholdAccountable
  extend ActiveSupport::Concern

  included do
    has_one :owned_household, class_name: "Household",
            foreign_key: :owner_id,
            inverse_of: :owner,
            dependent: :destroy

    has_one :household_membership, class_name: "HouseholdMember", dependent: :destroy
    has_one :member_household, through: :household_membership, source: :household
  end

  # The one household this user belongs to, whichever side they're on.
  def household
    owned_household || member_household
  end

  def household_owner?
    owned_household.present?
  end

  def household_admin?
    household_owner? || household_membership&.admin? || false
  end
end
