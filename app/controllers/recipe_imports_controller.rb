class RecipeImportsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!

  # Every import (URL or file) runs on Claude, so a household can only start
  # so many an hour. Counted per process (the cache store is in memory).
  rate_limit to: 20, within: 1.hour, only: %i[create create_from_file],
             by: -> { current_household.id },
             with: -> { redirect_to new_recipe_import_path, alert: "That's a lot of imports at once — please try again in a little while." }

  # Imports run on Sidekiq (ProcessRecipeImportJob), and the progress page
  # streams their updates as Turbo broadcasts over Redis.

  # Uploads wait in the database until the worker reads them. Base64 for
  # Claude grows a file by a third, and its requests top out at 32 MB.
  MAX_UPLOAD_SIZE = 20.megabytes

  def new
    @import_job = RecipeImportJob.new
  end

  def create
    if params[:url].blank?
      redirect_to new_recipe_import_path, alert: "Please enter a recipe URL."
      return
    end

    @import_job = current_user.recipe_import_jobs.create!(
      url: params[:url].strip,
      status: :pending,
      progress: 0,
      total_steps: 5
    )

    ProcessRecipeImportJob.perform_later(@import_job.id, "url")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "import_progress",
          partial: "recipe_imports/progress",
          locals: { import_job: @import_job }
        )
      end
      format.html { redirect_to recipe_import_path(@import_job) }
    end
  end

  def create_from_file
    file = params[:file]
    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      redirect_to new_recipe_import_path, alert: "Please select a file."
      return
    end

    if file.size > MAX_UPLOAD_SIZE
      redirect_to new_recipe_import_path, alert: "That file is too large — please upload one under #{MAX_UPLOAD_SIZE / 1.megabyte} MB."
      return
    end

    # Judged by the file's contents, not the type the browser claims for it.
    content_type = ClaudeFileContent.content_type_of(file)
    unless content_type
      redirect_to new_recipe_import_path, alert: "Unsupported file type. Please upload an image or PDF."
      return
    end

    # The worker may be in another container, so the upload travels with the
    # import rather than on this server's disk; it's cleared once read.
    @import_job = current_user.recipe_import_jobs.create!(
      url: nil,
      status: :pending,
      progress: 0,
      total_steps: 5,
      source_file: file.read,
      source_content_type: content_type
    )

    ProcessRecipeImportJob.perform_later(@import_job.id, "file")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "import_progress",
          partial: "recipe_imports/progress",
          locals: { import_job: @import_job }
        )
      end
      format.html { redirect_to recipe_import_path(@import_job) }
    end
  end

  def show
    @import_job = current_user.recipe_import_jobs.find(params[:id])

    if @import_job.completed?
      redirect_to recipe_path(@import_job.recipe)
    end
  end

  # The import pauses after matching so the user can vet each match. Whatever
  # they didn't tick loses its match and becomes a new ingredient.
  def confirm_ingredients
    @import_job = current_user.recipe_import_jobs.find(params[:id])

    # Claimed atomically, so a second submit (another tab, a resubmitted
    # request) can't also get past this and start a second run that saves
    # the recipe twice.
    unless @import_job.claim_confirmation!
      return redirect_to recipe_import_path(@import_job),
                         alert: "This import isn't waiting on ingredient confirmation."
    end

    @import_job.apply_ingredient_confirmations!(Array(params[:confirmed]))
    @import_job.update_progress(:resolving_with_ai, 0, @import_job.ingredient_count)

    ProcessRecipeImportJob.perform_later(@import_job.id, "resume")

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@import_job) }
      format.html { redirect_to recipe_import_path(@import_job) }
    end
  end
end