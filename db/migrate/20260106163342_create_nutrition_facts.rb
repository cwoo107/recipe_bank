class CreateNutritionFacts < ActiveRecord::Migration[8.1]
  def change
    create_table :nutrition_facts do |t|
      t.references :ingredient, null: false, foreign_key: true
      t.string :serving_unit
      t.float :serving_size
      t.float :total_fat
      t.float :total_carb
      t.float :protein

      t.timestamps
    end
  end
end
