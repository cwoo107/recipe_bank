class Ingredient < ApplicationRecord
  belongs_to :created_by, class_name: 'User', optional: true

  has_one  :nutrition_fact, dependent: :destroy
  has_many :recipe_ingredients, dependent: :destroy
  has_many :recipes, through: :recipe_ingredients
  has_many :ingredient_tags, dependent: :destroy
  has_many :tags, through: :ingredient_tags
  has_many :grocery_lists, dependent: :destroy

  validates :ingredient, presence: true

  def editable_by?(user)
    return false unless user
    created_by_id.nil? || created_by_id == user.id
  end
end