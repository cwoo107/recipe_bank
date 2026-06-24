class AddUserFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :user_favorites do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.timestamps
    end

    add_index :user_favorites, [:user_id, :recipe_id], unique: true

    # Migrate existing favorites: assign to the recipe's creator so no data is lost.
    # Any recipe currently marked favorite will become a favorite for its owner.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO user_favorites (user_id, recipe_id, created_at, updated_at)
          SELECT user_id, id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM recipes
          WHERE favorite = TRUE AND user_id IS NOT NULL
        SQL
      end
    end

    remove_column :recipes, :favorite, :boolean
  end
end