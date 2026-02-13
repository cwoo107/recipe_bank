class CreateIngredientTags < ActiveRecord::Migration[8.1]
  def change
    create_table :ingredient_tags do |t|
      t.references :ingredient, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end
  end
end
