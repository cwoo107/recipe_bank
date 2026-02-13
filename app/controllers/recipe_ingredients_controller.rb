class RecipeIngredientsController < ApplicationController
  before_action :set_recipe

  def create
    @recipe_ingredient = @recipe.recipe_ingredients.build(recipe_ingredient_params)

    if @recipe_ingredient.save
      redirect_to @recipe, notice: "Ingredient added successfully."
    else
      redirect_to @recipe, alert: "Failed to add ingredient."
    end
  end

  def destroy
    @recipe_ingredient = @recipe.recipe_ingredients.find(params[:id])
    @recipe_ingredient.destroy
    redirect_to @recipe, notice: "Ingredient removed."
  end

  private
  def set_recipe
    @recipe = Recipe.find(params[:recipe_id])
  end

  def recipe_ingredient_params
    params.require(:recipe_ingredient).permit(:ingredient_id, :quantity, :unit)
  end
end