class CreateCollectionRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :collection_recipes do |t|
      t.belongs_to :collection, null: false, foreign_key: true
      t.belongs_to :recipe, null: false, foreign_key: true

      t.timestamps
    end
  end
end
