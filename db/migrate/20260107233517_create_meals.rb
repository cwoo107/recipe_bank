class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :meals do |t|
      t.references :recipe, null: false, foreign_key: true
      t.string :meal_name
      t.date :date

      t.timestamps
    end
  end
end
