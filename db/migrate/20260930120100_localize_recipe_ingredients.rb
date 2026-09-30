# Recipes used to draw on one shared ingredient pool, so a recipe could point
# at an ingredient another household owns — and lose that line if they
# deleted it. This moves every such line onto its owner's household copy
# (made here if the household doesn't have one), and grocery list rows with
# them. Mirrors Ingredient#copy_for, but on stand-ins so it doesn't depend on
# app models.
class LocalizeRecipeIngredients < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  class MigrationNutritionFact < ActiveRecord::Base
    self.table_name = "nutrition_facts"
  end

  class MigrationIngredientTag < ActiveRecord::Base
    self.table_name = "ingredient_tags"
  end

  class MigrationTag < ActiveRecord::Base
    self.table_name = "tags"
  end

  class MigrationRecipeIngredient < ActiveRecord::Base
    self.table_name = "recipe_ingredients"
  end

  class MigrationRecipe < ActiveRecord::Base
    self.table_name = "recipes"
  end

  class MigrationGroceryList < ActiveRecord::Base
    self.table_name = "grocery_lists"
  end

  class MigrationHousehold < ActiveRecord::Base
    self.table_name = "households"
  end

  class MigrationMember < ActiveRecord::Base
    self.table_name = "household_members"
  end

  COPIED_COLUMNS = %w[ingredient brand family organic unit_price unit_servings].freeze

  def up
    [MigrationIngredient, MigrationRecipeIngredient, MigrationGroceryList].each(&:reset_column_information)

    household_of_user = {}
    owner_by_recipe   = MigrationRecipe.pluck(:id, :user_id).to_h

    MigrationRecipeIngredient.find_each do |line|
      user_id = owner_by_recipe[line.recipe_id]
      next unless user_id

      household_id = household_of_user.fetch(user_id) { household_of_user[user_id] = household_for(user_id) }
      next unless household_id

      ingredient = MigrationIngredient.find(line.ingredient_id)
      next if ingredient.household_id == household_id

      line.update_columns(ingredient_id: copy_for(ingredient, household_id, user_id).id)
    end

    # Grocery rows follow their household's copy where one now exists, so the
    # list keeps working if the original's owner deletes it.
    MigrationGroceryList.find_each do |row|
      ingredient = MigrationIngredient.find_by(id: row.ingredient_id)
      next if ingredient.nil? || ingredient.household_id == row.household_id

      copy = MigrationIngredient.find_by(household_id: row.household_id, source_ingredient_id: ingredient.id)
      row.update_columns(ingredient_id: copy.id) if copy
    end
  end

  def down
    # Irreversible data backfill — the copies are ordinary household ingredients now.
  end

  private

  def household_for(user_id)
    MigrationHousehold.where(owner_id: user_id).pick(:id) ||
      MigrationMember.where(user_id: user_id).pick(:household_id)
  end

  # An earlier copy of this ingredient, a same-named same-brand one the
  # household already has, or a fresh copy with its nutrition and tags.
  def copy_for(ingredient, household_id, user_id)
    MigrationIngredient.find_by(household_id: household_id, source_ingredient_id: ingredient.id) ||
      household_equivalent(ingredient, household_id) ||
      duplicate(ingredient, household_id, user_id)
  end

  def household_equivalent(ingredient, household_id)
    MigrationIngredient.where(household_id: household_id)
                       .where("LOWER(ingredient) = ?", ingredient.ingredient.to_s.strip.downcase)
                       .detect { |candidate| candidate.brand.to_s.strip.casecmp?(ingredient.brand.to_s.strip) }
  end

  def duplicate(ingredient, household_id, user_id)
    copy = MigrationIngredient.create!(
      ingredient.attributes.slice(*COPIED_COLUMNS).merge(
        "household_id" => household_id, "source_ingredient_id" => ingredient.id, "created_by_id" => user_id
      )
    )

    if (fact = MigrationNutritionFact.find_by(ingredient_id: ingredient.id))
      MigrationNutritionFact.create!(fact.attributes.except("id", "ingredient_id", "created_at", "updated_at")
                                         .merge("ingredient_id" => copy.id))
    end

    # Tags are personal, so they're mirrored into the recipe owner's own.
    MigrationIngredientTag.where(ingredient_id: ingredient.id).find_each do |link|
      tag = MigrationTag.find_by(id: link.tag_id) or next
      mine = if tag.user_id == user_id
               tag
             else
               MigrationTag.find_or_create_by!(user_id: user_id, tag: tag.tag) { |t| t.color = tag.color }
             end
      MigrationIngredientTag.create!(ingredient_id: copy.id, tag_id: mine.id)
    end

    copy
  end
end
