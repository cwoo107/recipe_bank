class CreateChoreCategories < ActiveRecord::Migration[8.1]
  DEFAULT_NAMES = [ "Standard Cleaning", "Chores", "Admin", "Deep Cleaning", "Home Maintenance" ].freeze

  def up
    create_table :chore_categories do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :chore_categories, [ :household_id, :position ]

    add_reference :chores, :chore_category, foreign_key: true

    # Seed the defaults onto every existing household, and file its existing
    # chores under "Chores" so none of them fall off the board.
    now = Time.current
    select_values("SELECT id FROM households").each do |household_id|
      DEFAULT_NAMES.each_with_index do |name, index|
        execute <<~SQL
          INSERT INTO chore_categories (household_id, name, position, created_at, updated_at)
          VALUES (#{household_id.to_i}, #{quote(name)}, #{index + 1}, #{quote(now)}, #{quote(now)})
        SQL
      end
      chores_id = select_value("SELECT id FROM chore_categories WHERE household_id = #{household_id.to_i} AND name = 'Chores'")
      execute "UPDATE chores SET chore_category_id = #{chores_id.to_i} WHERE household_id = #{household_id.to_i}"
    end
  end

  def down
    remove_reference :chores, :chore_category, foreign_key: true
    drop_table :chore_categories
  end
end
