class RecipeImportsController < ApplicationController
  # Imports run off the request thread so the progress page can stream
  # updates while they work. Tests swap in the inline runner.
  THREADED_RUNNER = ->(&work) {
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&work) }
  }
  INLINE_RUNNER = ->(&work) { work.call }

  class_attribute :background_runner, default: THREADED_RUNNER

  def new
    @import_job = RecipeImportJob.new
  end

  def create
    @import_job = current_user.recipe_import_jobs.create!(
      url: params[:url],
      status: :pending,
      progress: 0,
      total_steps: 5
    )

    job_id = @import_job.id
    background_runner.call { RecipeImporter.new(RecipeImportJob.find(job_id)).perform }

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
    unless params[:file].present?
      redirect_to new_recipe_import_path, alert: "Please select a file."
      return
    end

    file = params[:file]
    allowed_types = RecipeFileExtractor::SUPPORTED_TYPES
    unless allowed_types.include?(file.content_type)
      redirect_to new_recipe_import_path, alert: "Unsupported file type. Please upload an image or PDF."
      return
    end

    @import_job = current_user.recipe_import_jobs.create!(
      url: nil,
      status: :pending,
      progress: 0,
      total_steps: 5
    )

    # Read file into memory before passing to thread
    file_data   = file.read
    content_type = file.content_type

    job_id = @import_job.id
    background_runner.call do
      RecipeImporter.new(RecipeImportJob.find(job_id)).perform_from_file(file_data, content_type)
    end

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

    unless @import_job.awaiting_confirmation?
      return redirect_to recipe_import_path(@import_job),
                         alert: "This import isn't waiting on ingredient confirmation."
    end

    @import_job.apply_ingredient_confirmations!(Array(params[:confirmed]))
    @import_job.update_progress(:resolving_with_ai, 0, @import_job.ingredient_count)

    # Reload inside the worker rather than sharing this request's instance.
    job_id = @import_job.id
    background_runner.call { RecipeImporter.new(RecipeImportJob.find(job_id)).resume_after_confirmation }

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@import_job) }
      format.html { redirect_to recipe_import_path(@import_job) }
    end
  end
end