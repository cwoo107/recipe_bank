# Fills in the parts of a new ingredient the user shouldn't have to look up:
# its family, a typical unit price and servings-per-unit, and nutrition facts.
#
# Runs after the ingredient is saved so nobody waits on the AI round trip.
# Only blanks are filled — anything the user actually typed is left alone —
# and OllamaAssistant falls back to family-based estimates when the model
# isn't reachable, so this is safe to run with nothing listening.
class IngredientEnrichmentJob < ApplicationJob
  queue_as :default

  def perform(ingredient_id)
    ingredient = Ingredient.find_by(id: ingredient_id)
    return unless ingredient

    ai = OllamaAssistant.new(model: "llama2")

    ingredient.update!(family: guessed_family(ai, ingredient)) if ingredient.family.blank?

    estimate = estimate_for(ai, ingredient)
    return if estimate.blank?

    apply_pricing(ingredient, estimate)
    apply_nutrition(ingredient, estimate)

    broadcast_refreshed_recipes(ingredient)
  end

  private

  def guessed_family(ai, ingredient)
    classification = ai.classify_ingredient_families([{ name: ingredient.ingredient }])
                       .find { |c| c.is_a?(Hash) && c["name"] == ingredient.ingredient }

    classification&.dig("family").presence ||
      ai.send(:guess_family_programmatically, ingredient.ingredient)
  end

  # The AI path returns JSON (string keys); the offline fallback returns symbol
  # keys. Normalise so the callers below don't have to care.
  def estimate_for(ai, ingredient)
    raw = ai.estimate_nutrition_facts([{ name: ingredient.ingredient, family: ingredient.family }]).first
    return nil unless raw.is_a?(Hash)

    raw.with_indifferent_access
  end

  def apply_pricing(ingredient, estimate)
    updates = {}
    updates[:unit_price]    = estimate[:unit_price]    if ingredient.unit_price.blank?
    updates[:unit_servings] = estimate[:unit_servings] if ingredient.unit_servings.blank?

    ingredient.update!(updates) if updates.any? { |_, value| value.present? }
  end

  def apply_nutrition(ingredient, estimate)
    return if ingredient.nutrition_fact.present?

    ingredient.create_nutrition_fact!(
      serving_size: estimate[:serving_size],
      serving_unit: estimate[:serving_unit],
      calories:     estimate[:calories],
      protein:      estimate[:protein],
      total_fat:    estimate[:total_fat],
      total_carb:   estimate[:total_carb]
    )
  end

  # The recipe pages showing this ingredient were rendered before any of the
  # above existed — push the corrected row and macros out to whoever's looking.
  def broadcast_refreshed_recipes(ingredient)
    ingredient.recipe_ingredients.includes(:recipe).each do |line|
      recipe = line.recipe
      next unless recipe

      Turbo::StreamsChannel.broadcast_replace_to(
        recipe, target: "recipe_ingredient_#{line.id}",
        partial: "recipes/recipe_ingredient_row",
        locals: { recipe_ingredient: line, recipe: recipe }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        recipe, target: "macros_chart",
        partial: "recipes/macros_chart",
        locals: { recipe: recipe }
      )
    end
  end
end
