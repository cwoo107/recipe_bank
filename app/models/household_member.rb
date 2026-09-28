class HouseholdMember < ApplicationRecord
  belongs_to :household
  belongs_to :user, optional: true # passive members (e.g. children) have no login

  # Deleting a member shouldn't be blocked by (or leave dangling) chore assignments.
  has_many :chores,        foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee
  has_many :weekly_chores, foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee
  has_many :todos,         foreign_key: :assignee_id, dependent: :nullify, inverse_of: :assignee
  has_many :meal_assignments,           dependent: :destroy
  has_many :recurring_meal_assignments, dependent: :destroy

  # admin  => same level of control as the owner
  # limited => can view/use household data, cannot manage the household or members
  enum :role, { admin: 0, limited: 1 }, default: :limited, validate: true

  validates :name, presence: true
  validates :color, inclusion: { in: Palette::NAMES }
  validates :user_id, uniqueness: true, allow_nil: true
  validate :owner_stays_admin

  # Set when a color was deliberately chosen (the member form), so it's kept
  # even if it's the column default. Not persisted.
  attribute :color_chosen, :boolean, default: false

  before_validation :pick_unused_color, on: :create
  after_create :grow_household_family_size
  before_destroy :keep_owner_member, unless: :destroyed_by_association

  scope :with_login, -> { where.not(user_id: nil) }

  # The household owner's own row (see Household#owner_member).
  def owner?
    user_id.present? && household&.owner_id == user_id
  end

  def login?
    user_id.present?
  end

  def color_classes = Palette.person_classes(color)

  private

  # New members get the first color nobody in the household has yet (then
  # wrap around), unless one was picked.
  def pick_unused_color
    return if color_chosen? || household.nil?

    self.color = household.next_member_color
  end

  def owner_stays_admin
    errors.add(:role, "can't be changed for the owner") if owner? && !admin?
  end

  def grow_household_family_size
    household.grow_family_size_to_fit_members!
  end

  def keep_owner_member
    return unless owner?

    errors.add(:base, "The owner can't be removed from their household")
    throw :abort
  end
end