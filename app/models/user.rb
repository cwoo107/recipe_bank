class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :recipes,            dependent: :destroy
  has_many :meals,              dependent: :destroy
  has_many :grocery_lists,      dependent: :destroy
  has_many :tags,               dependent: :destroy
  has_many :recipe_import_jobs, dependent: :destroy
  has_many :collections,        dependent: :destroy
  has_many :created_ingredients, class_name: 'Ingredient',
                                  foreign_key: :created_by_id,
                                  dependent: :nullify

  has_many :user_favorites, dependent: :destroy
  has_many :favorited_recipes, through: :user_favorites, source: :recipe

  def favorited?(recipe)
    user_favorites.exists?(recipe: recipe)
  end
end
