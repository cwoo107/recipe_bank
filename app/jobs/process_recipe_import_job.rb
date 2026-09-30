# Runs a recipe import (a RecipeImportJob record) on Sidekiq — each stage
# enqueued by RecipeImportsController:
#
#   "url"    — scrape a recipe page, match ingredients, pause for the user
#   "file"   — extract a recipe from an uploaded photo/PDF, then the same
#   "resume" — after the user confirms their matches, save the recipe
#
# Progress reaches the page as Turbo broadcasts over Action Cable (Redis),
# which is how updates sent from this worker get to the browser.
#
# Failures aren't retried: RecipeImporter has already recorded the error on
# the import for the user to see, and a retry would redo the scrape and AI
# calls — or, for "resume", race the user starting over. Sidekiq still logs
# the exception.
class ProcessRecipeImportJob < ApplicationJob
  queue_as :default

  STAGES = %w[url file resume].freeze

  discard_on StandardError do |job, error|
    Rails.logger.error "ProcessRecipeImportJob #{job.arguments.inspect} failed: #{error.class}: #{error.message}"
  end

  def perform(import_job_id, stage)
    raise ArgumentError, "unknown import stage #{stage.inspect}" unless STAGES.include?(stage)

    # Deleted in the meantime (e.g. recipe_imports:clear_stuck) — nothing to do.
    import_job = RecipeImportJob.find_by(id: import_job_id)
    return unless import_job

    importer = RecipeImporter.new(import_job)
    case stage
    when "url"    then importer.perform
    when "file"   then importer.perform_from_file
    when "resume" then importer.resume_after_confirmation
    end
  end
end
