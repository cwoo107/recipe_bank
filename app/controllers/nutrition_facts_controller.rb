class NutritionFactsController < ApplicationController
  before_action :set_ingredient
  before_action :set_nutrition_fact, only: [:edit, :update, :destroy]

  def create
    @nutrition_fact = @ingredient.build_nutrition_fact(nutrition_fact_params)

    if @nutrition_fact.save
      redirect_to @ingredient, notice: "Nutrition facts added successfully."
    else
      redirect_to @ingredient, alert: "Failed to add nutrition facts."
    end
  end

  def edit
  end

  def update
    if @nutrition_fact.update(nutrition_fact_params)
      redirect_to @ingredient, notice: "Nutrition facts updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @nutrition_fact.destroy
    redirect_to @ingredient, notice: "Nutrition facts deleted."
  end

  private
  def set_ingredient
    @ingredient = Ingredient.find(params[:ingredient_id])
  end

  def set_nutrition_fact
    @nutrition_fact = @ingredient.nutrition_fact
  end

  def nutrition_fact_params
    params.require(:nutrition_fact).permit(:serving_size, :serving_unit, :total_fat, :total_carb, :protein, :calories)
  end
end