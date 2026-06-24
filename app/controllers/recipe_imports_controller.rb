class RecipeImportsController < ApplicationController
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

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        RecipeImporter.new(@import_job).perform
      end
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
end