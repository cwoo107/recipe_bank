class RecipeTagsController < ApplicationController
  before_action :set_recipe

  def create
    @recipe_tag = @recipe.recipe_tags.build(recipe_tag_params)

    if @recipe_tag.save
      redirect_to @recipe, notice: "Tag added successfully."
    else
      redirect_to @recipe, alert: "Failed to add tag."
    end
  end

  def destroy
    @recipe_tag = @recipe.recipe_tags.find(params[:id])
    @recipe_tag.destroy
    redirect_to @recipe, notice: "Tag removed."
  end

  private
  def set_recipe
    @recipe = Recipe.find(params[:recipe_id])
  end

  def recipe_tag_params
    params.require(:recipe_tag).permit(:tag_id)
  end
end