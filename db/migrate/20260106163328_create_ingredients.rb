class CreateIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :ingredients do |t|
      t.string :ingredient
      t.string :family
      t.string :brand
      t.boolean :organic

      t.timestamps
    end
  end
end
