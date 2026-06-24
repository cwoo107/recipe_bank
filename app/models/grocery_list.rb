class GroceryList < ApplicationRecord
  belongs_to :ingredient
  belongs_to :user

  serialize :meal_ids, type: Array, coder: JSON

  def meals
    Meal.where(id: meal_ids)
  end
end