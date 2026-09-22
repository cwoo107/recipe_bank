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

  # Tags are personal, so copying a recipe between users means re-pointing its
  # tags at the saving user's equivalents, creating them if they're missing.
  def mirror_for(user)
    return self if user_id == user.id

    user.tags.find_or_create_by!(tag: tag) { |t| t.color = color }
  end
end