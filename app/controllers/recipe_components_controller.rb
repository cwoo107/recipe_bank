# Attaching one recipe to another as an ingredient.
class RecipeComponentsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_recipe
  before_action :set_component, only: %i[update destroy]

  def create
    # Only what the picker offers: the household's own recipes, or public
    # ones. Anything else (another household's private recipe, by posting
    # its id) is refused rather than attached.
    component_recipe_id = component_params[:component_recipe_id]
    if component_recipe_id.present? && !Recipe.browsable_by_household(current_household).exists?(component_recipe_id)
      return redirect_to @recipe, alert: "That recipe isn't available to add."
    end

    @component = @recipe.recipe_components.build(component_params)

    if @component.save
      respond_with_refreshed_recipe(notice: "Added #{@component.component_recipe.title}.")
    else
      redirect_to @recipe, alert: @component.errors.full_messages.to_sentence
    end
  end

  def update
    if @component.update(component_params.slice(:multiplier))
      respond_with_refreshed_recipe
    else
      redirect_to @recipe, alert: @component.errors.full_messages.to_sentence
    end
  end

  def destroy
    title = @component.component_recipe.title
    @component.destroy!

    respond_with_refreshed_recipe(notice: "Removed #{title}.")
  end

  private

  # A component changes both panels and the macros, so all three get resent
  # rather than trying to patch one section.
  def respond_with_refreshed_recipe(notice: nil)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("recipe_ingredients_section",
                               partial: "recipes/recipe_ingredients", locals: { recipe: @recipe }),
          turbo_stream.replace("recipe_steps",
                               partial: "recipes/recipe_steps", locals: { recipe: @recipe }),
          turbo_stream.replace("macros_chart",
                               partial: "recipes/macros_chart", locals: { recipe: @recipe }),
          (notice && turbo_stream.prepend("flash", partial: "shared/flash", locals: { notice: notice }))
        ].compact
      end
      format.html { redirect_to @recipe, notice: notice }
    end
  end

  # Only the owner reshapes a recipe, matching what the page offers.
  def set_recipe
    @recipe = current_user.recipes.find(params[:recipe_id])
  end

  def set_component
    @component = @recipe.recipe_components.find(params[:id])
  end

  def component_params
    params.expect(recipe_component: [:component_recipe_id, :multiplier])
  end
end
