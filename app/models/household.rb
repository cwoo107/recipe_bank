class Household < ApplicationRecord
  belongs_to :owner, class_name: "User", inverse_of: :owned_household

  has_many :household_members, dependent: :destroy
  has_many :members, through: :household_members, source: :user

  has_many :meals,            dependent: :destroy
  has_many :recurring_meals,  dependent: :destroy
  has_many :todos,            dependent: :destroy
  has_many :chores,           dependent: :destroy
  has_many :weekly_chores,    dependent: :destroy
  has_many :grocery_lists,    dependent: :destroy
  has_many :calendar_sources, dependent: :destroy
  has_many :calendar_events,  dependent: :destroy
  has_many :weekly_plans,     dependent: :destroy

  validates :family_name, presence: true
  validates :minutes_per_day, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def self.default_family_name_for(user)
    handle = user.email.to_s.split("@").first.presence || "New"
    "#{handle.titleize}'s Household"
  end

  def owner?(user)
    owner_id == user&.id
  end

  # Owner + admin sub-users have full control.
  def admin?(user)
    owner?(user) || household_members.admin.exists?(user_id: user&.id)
  end

  def member?(user)
    owner?(user) || household_members.exists?(user_id: user&.id)
  end

  # Everyone who can log in and see this household's data.
  def users
    User.where(id: [owner_id] + household_members.with_login.pluck(:user_id))
  end

  # Creates a sub-user with their own Devise login and a membership row, then
  # emails them a set-your-password link. Returns the (possibly unpersisted,
  # error-laden) HouseholdMember either way, so controllers can re-render forms.
  def invite_member(name: nil, email: nil, role: :limited)
    member = household_members.new(name:, role:)

    transaction do
      user = User.new(email:, password: SecureRandom.base58(24), skip_household_provisioning: true)
      user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
      user.save!

      member.user = user
      member.save!

      user.send_reset_password_instructions
    end

    member
  rescue ActiveRecord::RecordInvalid => e
    member.errors.merge!(e.record.errors) unless e.record.equal?(member)
    member
  end
end