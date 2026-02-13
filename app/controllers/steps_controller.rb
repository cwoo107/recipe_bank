class StepsController < ApplicationController
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
      redirect_to @recipe, notice: "Step added successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @step.update(step_params)
      redirect_to @recipe, notice: "Step updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @step.destroy
    redirect_to @recipe, notice: "Step deleted."
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