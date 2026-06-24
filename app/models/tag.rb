class Tag < ApplicationRecord
  belongs_to :user

  has_many :recipe_tags,    dependent: :destroy
  has_many :recipes,        through: :recipe_tags
  has_many :ingredient_tags, dependent: :destroy
  has_many :ingredients,    through: :ingredient_tags

  validates :tag,   presence: true
  validates :color, presence: true

  # Scoped lookup — tags are personal, so we always filter by user
  scope :for_user, ->(user) { where(user: user) }
end