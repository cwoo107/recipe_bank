class CreateRestockCategories < ActiveRecord::Migration[8.1]
  # Frozen snapshots of the tables involved, so this migration keeps working
  # the same way regardless of how the real models evolve later.
  class MigrationHousehold < ApplicationRecord
    self.table_name = "households"
  end

  class MigrationCategory < ApplicationRecord
    self.table_name = "restock_categories"
  end

  class MigrationItem < ApplicationRecord
    self.table_name = "restock_items"
  end

  # The five columns every household starts with (Misc Supplies is no longer
  # a default — see the "Add a restock category" tile that replaces it).
  DEFAULT_NAMES = [ "Bathrooms", "Laundry Room", "Kitchen", "Pantry", "Refrigerator/Freezer" ].freeze

  # Maps the old hardcoded `category` slugs to their display names, so
  # existing items land in a same-named category instead of losing their
  # grouping.
  LEGACY_LABELS = {
    "bathrooms"            => "Bathrooms",
    "laundry_room"         => "Laundry Room",
    "kitchen"              => "Kitchen",
    "pantry"               => "Pantry",
    "refrigerator_freezer" => "Refrigerator/Freezer",
    "misc_supplies"        => "Misc Supplies"
  }.freeze

  def up
    create_table :restock_categories do |t|
      t.string  :name,         null: false
      t.integer :position,     null: false, default: 0
      t.integer :household_id, null: false

      t.timestamps
    end

    add_index :restock_categories, [ :household_id, :position ]
    add_foreign_key :restock_categories, :households

    add_reference :restock_items, :restock_category, null: true, foreign_key: true

    MigrationHousehold.reset_column_information
    MigrationCategory.reset_column_information
    MigrationItem.reset_column_information

    MigrationHousehold.find_each do |household|
      categories_by_name = {}

      DEFAULT_NAMES.each_with_index do |name, index|
        categories_by_name[name] = MigrationCategory.create!(household_id: household.id, name: name, position: index + 1)
      end

      next_position = DEFAULT_NAMES.size + 1
      existing_slugs = MigrationItem.where(household_id: household.id).distinct.pluck(:category)

      existing_slugs.each do |slug|
        label = LEGACY_LABELS.fetch(slug, slug.to_s.titleize)
        category = categories_by_name[label] ||= MigrationCategory.create!(
          household_id: household.id, name: label, position: next_position
        )
        next_position += 1 if category.position == next_position

        MigrationItem.where(household_id: household.id, category: slug).update_all(restock_category_id: category.id)
      end
    end

    change_column_null :restock_items, :restock_category_id, false

    remove_index :restock_items, column: [ :household_id, :category ], if_exists: true
    remove_index :restock_items, column: [ :household_id, :category, :position ], if_exists: true
    remove_column :restock_items, :category

    add_index :restock_items, [ :restock_category_id, :position ]
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
