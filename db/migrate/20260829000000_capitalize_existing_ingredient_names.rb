class CapitalizeExistingIngredientNames < ActiveRecord::Migration[8.1]
  class Ingredient < ApplicationRecord
  end

  def up
    Ingredient.reset_column_information
    Ingredient.find_each do |ingredient|
      capitalized = ingredient.ingredient&.strip&.capitalize
      next if capitalized.nil? || capitalized == ingredient.ingredient
      ingredient.update_column(:ingredient, capitalized)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
