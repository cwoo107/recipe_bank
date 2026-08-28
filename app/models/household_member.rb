class HouseholdMember < ApplicationRecord
  belongs_to :household
  belongs_to :user, optional: true # passive members (e.g. children) have no login

  # Deleting a member shouldn't be blocked by (or leave dangling) chore assignments.
  has_many :chores,        foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee
  has_many :weekly_chores, foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee

  # admin  => same level of control as the owner
  # limited => can view/use household data, cannot manage the household or members
  enum :role, { admin: 0, limited: 1 }, default: :limited, validate: true

  validates :name, presence: true
  validates :user_id, uniqueness: true, allow_nil: true
  validate :user_is_not_the_owner

  scope :with_login, -> { where.not(user_id: nil) }

  private

  def user_is_not_the_owner
    return if user_id.blank?

    if household&.owner_id == user_id
      errors.add(:user, "is the owner and doesn't need a membership")
    end
  end
end