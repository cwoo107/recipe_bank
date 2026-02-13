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
end