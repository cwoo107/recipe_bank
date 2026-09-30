# Ingredients move from one shared pool to per-household libraries. Each
# ingredient belongs to the household of whoever created it; recipes that
# point at another household's ingredient are re-homed by the next migration,
# LocalizeRecipeIngredients.
class AddHouseholdToIngredients < ActiveRecord::Migration[8.1]
  def up
    add_reference :ingredients, :household, foreign_key: true
    # The ingredient a household copy was made from, so copying the same
    # recipe twice (or two recipes sharing an ingredient) reuses one copy.
    add_reference :ingredients, :source_ingredient, foreign_key: { to_table: :ingredients }

    execute <<~SQL
      UPDATE ingredients
         SET household_id = COALESCE(
               (SELECT households.id FROM households
                 WHERE households.owner_id = ingredients.created_by_id LIMIT 1),
               (SELECT household_members.household_id FROM household_members
                 WHERE household_members.user_id = ingredients.created_by_id LIMIT 1)
             )
       WHERE household_id IS NULL AND created_by_id IS NOT NULL
    SQL
  end

  def down
    remove_reference :ingredients, :source_ingredient, foreign_key: { to_table: :ingredients }
    remove_reference :ingredients, :household, foreign_key: true
  end
end
