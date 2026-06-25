class CollectionRecipesController < ApplicationController
  before_action :set_collection_and_recipe

  def create
    @collection_recipe = @collection.collection_recipes.build(recipe: @recipe)

    if @collection_recipe.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "collection_button_#{@recipe.id}",
              partial: "collections/collection_button",
              locals: { recipe: @recipe }
            ),
            turbo_stream.prepend(
              "flash",
              partial: "shared/flash",
              locals: { notice: "Added to #{@collection.title}." }
            )
          ]
        end
        format.html { redirect_back fallback_location: recipes_path, notice: "Added to #{@collection.title}." }
      end
    else
      redirect_back fallback_location: recipes_path, alert: "Already in this collection."
    end
  end

  def destroy
    @collection_recipe = @collection.collection_recipes.find_by!(recipe: @recipe)
    @collection_recipe.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # On recipes index — update the collection button state
          turbo_stream.replace(
            "collection_button_#{@recipe.id}",
            partial: "collections/collection_button",
            locals: { recipe: @recipe }
          ),
          # On collections show — remove the recipe row
          turbo_stream.remove("collection_recipe_#{@recipe.id}"),
          turbo_stream.prepend(
            "flash",
            partial: "shared/flash",
            locals: { notice: "Removed from #{@collection.title}." }
          )
        ]
      end
      format.html { redirect_back fallback_location: recipes_path, notice: "Removed from #{@collection.title}." }
    end
  end

  private

  def set_collection_and_recipe
    @collection = current_user.collections.find(params[:collection_recipe][:collection_id])
    @recipe     = Recipe.find(params[:collection_recipe][:recipe_id])
  end
end