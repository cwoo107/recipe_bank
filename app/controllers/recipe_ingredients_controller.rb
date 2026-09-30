class RecipeIngredientsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_recipe

  # Adds a line for a picked ingredient — or for a name typed into the
  # picker that isn't in the library yet, which is added along with the
  # line: copied from the shared catalog if it's there, otherwise created
  # from just the name. Either way IngredientEnrichmentJob fills in whatever
  # family, cost and nutrition it's still missing.
  def create
    @recipe_ingredient = @recipe.recipe_ingredients.build(recipe_ingredient_params)
    added = nil # :copied or :created, when the line brings a new ingredient

    saved = RecipeIngredient.transaction do
      if @recipe_ingredient.ingredient_id.blank? && (typed = typed_ingredient)
        added = typed.new_record? ? :created : (:copied if typed.previously_new_record?)
        @recipe_ingredient.ingredient = typed
      end

      # Saves a new ingredient first; a failed line rolls back a catalog copy.
      @recipe_ingredient.save || raise(ActiveRecord::Rollback)
    end

    if saved
      new_ingredient = @recipe_ingredient.ingredient
      IngredientEnrichmentJob.perform_later(new_ingredient.id) if added && new_ingredient.needs_enrichment?

      respond_to do |format|
        format.turbo_stream do
          streams = [
            turbo_stream.replace("recipe_ingredients_section", partial: "recipes/recipe_ingredients", locals: { recipe: @recipe }),
            turbo_stream.replace("new_ingredient", partial: "recipes/new_ingredient"),
            turbo_stream.replace("macros_chart", partial: "recipes/macros_chart", locals: { recipe: @recipe })
          ]
          if added
            notice = added == :copied ? "Added #{new_ingredient.ingredient} to your ingredients, with its cost and nutrition." :
                                        "Added #{new_ingredient.ingredient} to your ingredients. We're estimating its cost and nutrition now."
            streams << turbo_stream.update("flash", partial: "shared/flash", locals: { notice: })
          end
          render turbo_stream: streams
        end
        format.html { redirect_to @recipe, notice: "Ingredient added." }
      end
    else
      redirect_to @recipe, alert: "Failed to add ingredient."
    end
  end

  # Inline quantity/unit edits from the recipe page's edit mode. The row is
  # re-rendered so the scaler picks up the new base quantity, and the macros
  # chart because the amounts feed it.
  def update
    @recipe_ingredient = @recipe.recipe_ingredients.find(params[:id])

    if @recipe_ingredient.update(recipe_ingredient_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("recipe_ingredient_#{@recipe_ingredient.id}",
                                 partial: "recipes/recipe_ingredient_row",
                                 locals: { recipe_ingredient: @recipe_ingredient, recipe: @recipe }),
            turbo_stream.replace("macros_chart", partial: "recipes/macros_chart", locals: { recipe: @recipe })
          ]
        end
        format.html { redirect_to @recipe, notice: "Ingredient updated." }
      end
    else
      redirect_to @recipe, alert: "Failed to update ingredient."
    end
  end

  def destroy
    @recipe_ingredient = @recipe.recipe_ingredients.find(params[:id])
    @recipe_ingredient.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("recipe_ingredient_#{@recipe_ingredient.id}"),
          turbo_stream.replace("macros_chart", partial: "recipes/macros_chart", locals: { recipe: @recipe })
        ]
      end
      format.html { redirect_to @recipe, notice: "Ingredient removed." }
    end
  end

  private

  # Every action here mutates the recipe, and the page only offers these
  # controls to the owner, so scope the lookup the same way.
  def set_recipe
    @recipe = current_user.recipes.find(params[:recipe_id])
  end

  def recipe_ingredient_params
    params.require(:recipe_ingredient).permit(:ingredient_id, :quantity, :unit, :optional)
  end

  # What was typed into the picker when no existing ingredient was picked.
  def typed_ingredient
    name = params.dig(:recipe_ingredient, :new_ingredient_name).to_s.squish
    Ingredient.find_or_initialize_for(current_household, name, created_by: current_user) if name.present?
  end
end