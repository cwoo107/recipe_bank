# Tags belong to the household now, like recipes and ingredients, instead of
# to whoever made them:
#   1. each tag moves to its creator's household (the one they own, else the
#      one they're a member of);
#   2. same-named tags within a household (two members each made "Dinner")
#      merge into one, every recipe and ingredient keeping its tag;
#   3. every household gets the default set (Tag::DEFAULTS at the time of
#      writing — copied here so later edits to the list don't change what
#      this migration did).
# user_id stays as who created a tag (nil for the defaults).
class MoveTagsToHouseholds < ActiveRecord::Migration[8.1]
  DEFAULTS = [
    [ "Breakfast",      "#d4b157" ],
    [ "Lunch",          "#7a9d9d" ],
    [ "Dinner",         "#577584" ],
    [ "Dessert",        "#a67a7f" ],
    [ "Quick & Easy",   "#7a9d9d" ],
    [ "Healthy",        "#7a8f62" ],
    [ "Vegetarian",     "#7a8f62" ],
    [ "Gluten Free",    "#d4b157" ],
    [ "Comfort Food",   "#b5806a" ],
    [ "BBQ & Grilling", "#a67a7f" ]
  ].freeze

  class MigrationTag < ActiveRecord::Base
    self.table_name = "tags"
  end

  class MigrationRecipeTag < ActiveRecord::Base
    self.table_name = "recipe_tags"
  end

  class MigrationIngredientTag < ActiveRecord::Base
    self.table_name = "ingredient_tags"
  end

  class MigrationHousehold < ActiveRecord::Base
    self.table_name = "households"
  end

  class MigrationHouseholdMember < ActiveRecord::Base
    self.table_name = "household_members"
  end

  def up
    add_reference :tags, :household, foreign_key: true, index: true

    MigrationTag.reset_column_information
    MigrationTag.where.not(user_id: nil).find_each do |tag|
      household_id = MigrationHousehold.where(owner_id: tag.user_id).pick(:id) ||
                     MigrationHouseholdMember.where(user_id: tag.user_id).pick(:household_id)
      tag.update_columns(household_id: household_id) if household_id
    end

    merge_duplicates
    seed_defaults

    add_index :tags, [ :household_id, :tag ], unique: true
  end

  def down
    remove_index :tags, [ :household_id, :tag ]
    remove_reference :tags, :household, foreign_key: true, index: true
  end

  private

  def merge_duplicates
    MigrationTag.where.not(household_id: nil).order(:id).group_by { |tag| [ tag.household_id, tag.tag.to_s.strip.downcase ] }.each_value do |tags|
      keeper, *duplicates = tags
      duplicates.each do |duplicate|
        [ [ MigrationRecipeTag, :recipe_id ], [ MigrationIngredientTag, :ingredient_id ] ].each do |model, owner|
          model.where(tag_id: duplicate.id).find_each do |link|
            if model.exists?(owner => link[owner], tag_id: keeper.id)
              link.delete
            else
              link.update_columns(tag_id: keeper.id)
            end
          end
        end
        duplicate.delete
      end
    end
  end

  def seed_defaults
    now = Time.current
    MigrationHousehold.pluck(:id).each do |household_id|
      existing = MigrationTag.where(household_id: household_id).pluck(:tag).map { |name| name.to_s.strip.downcase }
      DEFAULTS.each do |name, color|
        next if existing.include?(name.downcase)

        MigrationTag.create!(household_id: household_id, tag: name, color: color, created_at: now, updated_at: now)
      end
    end
  end
end
