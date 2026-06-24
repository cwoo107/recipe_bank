class RecipeImportJob < ApplicationRecord
  belongs_to :recipe, optional: true
  belongs_to :user

  broadcasts_to ->(job) { "recipe_import_#{job.id}" }, inserts_by: :replace

  enum :status, {
    pending:              'pending',
    fetching_html:        'fetching_html',
    parsing_recipe:       'parsing_recipe',
    matching_ingredients: 'matching_ingredients',
    resolving_with_ai:    'resolving_with_ai',
    creating_recipe:      'creating_recipe',
    completed:            'completed',
    failed:               'failed'
  }

  def update_progress(step, current = nil, total = nil)
    updates = { status: step, current_step: step.to_s.humanize }
    updates[:progress]    = current if current
    updates[:total_steps] = total   if total
    update!(updates)
  end

  def ingredient_count
    scraped_data&.dig('ingredients')&.length || 0
  end

  def matched_ingredient_count
    if matched_ingredients.present?
      matched_ingredients.count { |r| r.is_a?(Hash) && r['match'].present? }
    elsif matching_ingredients?
      progress.to_i
    else
      0
    end
  end

  def ingredient_match_summary
    total = ingredient_count
    return "Matching ingredients" if total.zero?

    if matching_ingredients?
      "Matching ingredients (#{progress.to_i} / #{total})"
    else
      "Matched #{matched_ingredient_count} of #{total} ingredients"
    end
  end
end