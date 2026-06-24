# app/models/recipe_import_job.rb
class RecipeImportJob < ApplicationRecord
  belongs_to :recipe, optional: true

  broadcasts_to ->(job) { "recipe_import_#{job.id}" }, inserts_by: :replace

  enum :status, {
    pending: 'pending',
    fetching_html: 'fetching_html',
    parsing_recipe: 'parsing_recipe',
    matching_ingredients: 'matching_ingredients',
    resolving_with_ai: 'resolving_with_ai',
    creating_recipe: 'creating_recipe',
    completed: 'completed',
    failed: 'failed'
  }


  def update_progress(step, current = nil, total = nil)
    updates = {
      status: step,
      current_step: step.to_s.humanize
    }
    updates[:progress] = current if current
    updates[:total_steps] = total if total

    update!(updates)
  end

  # Total number of ingredients in the scraped recipe.
  def ingredient_count
    scraped_data&.dig('ingredients')&.length || 0
  end

  # How many ingredients were matched to existing DB records.
  # Only meaningful once matching_ingredients or later steps have run.
  # Uses matched_ingredients JSON (set after matching completes) when available,
  # falls back to the live progress counter during the matching step itself.
  def matched_ingredient_count
    if matched_ingredients.present?
      matched_ingredients.count { |r| r.is_a?(Hash) && r['match'].present? }
    elsif matching_ingredients?
      progress.to_i
    else
      0
    end
  end

  # Human-readable summary for the matching step, correct at every lifecycle stage.
  # During matching:  "Matching ingredients (3 / 16)"
  # After matching:   "Matched 12 of 16 ingredients"
  def ingredient_match_summary
    total = ingredient_count
    return "Matching ingredients" if total.zero?

    if matching_ingredients?
      "Matching ingredients (#{progress.to_i} / #{total})"
    else
      matched = matched_ingredient_count
      "Matched #{matched} of #{total} ingredients"
    end
  end
end