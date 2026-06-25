class Collection < ApplicationRecord
  belongs_to :user
  has_many :collection_recipes, dependent: :destroy
  has_many :recipes, through: :collection_recipes

  validates :title, presence: true

  scope :visible_to, ->(user) {
    where(public: true).or(where(user: user))
  }

  def owned_by?(user)
    self.user_id == user&.id
  end
end
