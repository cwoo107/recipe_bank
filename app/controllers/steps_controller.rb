class StepsController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_recipe
  before_action :set_step, only: %i[ edit update destroy ]

  def new
    @step = @recipe.steps.build
  end

  def edit
  end

  def create
    @step = @recipe.steps.build(step_params)

    if @step.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("recipe_steps", partial: "recipes/recipe_steps", locals: { recipe: @recipe })
        end
        format.html { redirect_to @recipe, notice: "Step added successfully." }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @step.update(step_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(dom_id(@step), partial: "steps/step", locals: { recipe: @recipe, step: @step })
        end
        format.html { redirect_to @recipe, notice: "Step updated successfully." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @step.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("recipe_steps", partial: "recipes/recipe_steps", locals: { recipe: @recipe })
      end
      format.html { redirect_to @recipe, notice: "Step deleted." }
    end
  end

  def reorder
    params[:order].each_with_index do |id, index|
      @recipe.steps.find(id).update(position: index + 1)
    end

    head :ok
  end

  private
  def set_recipe
    @recipe = Recipe.find(params[:recipe_id])
  end

  def set_step
    @step = @recipe.steps.find(params[:id])
  end

  def step_params
    params.require(:step).permit(:content)
  end
end