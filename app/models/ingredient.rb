class Ingredient < ApplicationRecord
  has_many :recipe_ingredients, dependent: :restrict_with_error
  has_many :recipes, through: :recipe_ingredients
  has_one :nutrition_fact, dependent: :destroy
  has_many :grocery_lists, dependent: :destroy

  validates :ingredient, presence: true

  # default_scope { order(favorite: :desc) }

end