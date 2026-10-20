class RecipeTagsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_recipe

  def create
    # Only this household's own tags.
    tag = current_household.tags.find_by(id: recipe_tag_params[:tag_id])
    @recipe_tag = @recipe.recipe_tags.build(tag: tag)

    if tag && @recipe_tag.save
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
  # Only the household's own recipes get tagged — not public ones it can see.
  def set_recipe
    @recipe = Recipe.for_household(current_household).find(params[:recipe_id])
  end

  def recipe_tag_params
    params.require(:recipe_tag).permit(:tag_id)
  end
end