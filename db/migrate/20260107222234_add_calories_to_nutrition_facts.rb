class AddCaloriesToNutritionFacts < ActiveRecord::Migration[8.1]
  def change
    add_column :nutrition_facts, :calories, :integer
  end
end
