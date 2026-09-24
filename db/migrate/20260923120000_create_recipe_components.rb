class CreateRecipeComponents < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_components do |t|
      t.references :parent_recipe,    null: false, foreign_key: { to_table: :recipes }
      t.references :component_recipe, null: false, foreign_key: { to_table: :recipes }
      # How many batches of the component this recipe calls for.
      t.float   :multiplier, null: false, default: 1.0
      t.integer :position

      t.timestamps
    end

    add_index :recipe_components, [:parent_recipe_id, :component_recipe_id],
              unique: true, name: "index_recipe_components_uniqueness"
  end
end
