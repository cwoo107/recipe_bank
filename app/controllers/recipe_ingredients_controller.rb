class RecipeIngredientsController < ApplicationController
  before_action :set_recipe

  def create
    @recipe_ingredient = @recipe.recipe_ingredients.build(recipe_ingredient_params)

    if @recipe_ingredient.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("recipe_ingredients", partial: "recipes/recipe_ingredient_row", locals: { recipe_ingredient: @recipe_ingredient }),
            turbo_stream.replace("new_ingredient", partial: "recipes/new_ingredient"),
            turbo_stream.replace("macros_chart", partial: "recipes/macros_chart", locals: { recipe: @recipe })
          ]
        end
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
                                 locals: { recipe_ingredient: @recipe_ingredient }),
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
    params.require(:recipe_ingredient).permit(:ingredient_id, :quantity, :unit)
  end
end