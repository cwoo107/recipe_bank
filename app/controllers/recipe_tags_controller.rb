class RecipeTagsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_recipe

  # Params: { recipe_tag: { tag_names: "Dinner, Quick & Easy" } } — from the
  # tag picker. Only this household's own tags; names it doesn't have yet
  # become new tags.
  def create
    names = recipe_tag_params[:tag_names].to_s.split(",").map(&:strip).compact_blank.uniq(&:downcase)
    return redirect_to(@recipe, alert: "Pick a tag to add.") if names.empty?

    tags = names.map { |name| Tag.find_or_create_for(current_household, name, user: current_user) }
    (tags - @recipe.tags).each { |tag| @recipe.recipe_tags.create!(tag: tag) }

    redirect_to @recipe, notice: tags.one? ? "Tag added." : "Tags added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @recipe, alert: e.record.errors.full_messages.to_sentence
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
    params.require(:recipe_tag).permit(:tag_names)
  end
end