class AddUserOwnership < ActiveRecord::Migration[8.1]
  def change
    # Recipes: owned by creator, have visibility
    add_reference :recipes, :user, null: true, foreign_key: true
    add_column    :recipes, :visibility, :string, null: false, default: 'public'

    # Meals: private to the user who planned them
    add_reference :meals, :user, null: true, foreign_key: true

    # Grocery lists: private to the user
    add_reference :grocery_lists, :user, null: true, foreign_key: true

    # Tags: private to the user who created them
    add_reference :tags, :user, null: true, foreign_key: true

    # Recipe import jobs: private to the user who ran them
    add_reference :recipe_import_jobs, :user, null: true, foreign_key: true

    # Ingredients: globally shared, but we track who created each one
    # for edit/delete gating. Optional so existing records aren't broken.
    add_reference :ingredients, :created_by, null: true,
                  foreign_key: { to_table: :users }

    # Indexes for common query patterns
    add_index :recipes,           :visibility
    add_index :recipes,           [:user_id, :visibility]
    add_index :meals,             :user_id unless index_exists?(:meals, :user_id)
    add_index :grocery_lists,     :user_id unless index_exists?(:grocery_lists, :user_id)
    add_index :tags,              :user_id unless index_exists?(:tags, :user_id)
    add_index :recipe_import_jobs,:user_id unless index_exists?(:recipe_import_jobs, :user_id)
  end

end
