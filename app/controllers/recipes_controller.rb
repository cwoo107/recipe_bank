class RecipesController < ApplicationController
  before_action :set_recipe, only: %i[ show edit update toggle_favorite destroy ]

  def index
    @recipes = Recipe.includes(:tags, :recipe_ingredients, :steps).all

    if params[:query].present?
      @recipes = @recipes.where('title LIKE ? OR description LIKE ?',
                                "%#{params[:query]}%", "%#{params[:query]}%")
    end

    if params[:filter].present?
      @recipes = @recipes.joins(:tags).where(tags: { id: params[:filter] })
    end

    if params[:sort].present?
      sort_column = params[:sort]
      sort_direction = params[:direction] == 'desc' ? :desc : :asc

      case sort_column
      when 'ingredients'
        @recipes = @recipes.left_joins(:recipe_ingredients)
                           .group('recipes.id')
                           .order("COUNT(recipe_ingredients.id) #{sort_direction}")
      when 'steps'
        @recipes = @recipes.left_joins(:steps)
                           .group('recipes.id')
                           .order("COUNT(steps.id) #{sort_direction}")
      when 'tags'
        @recipes = @recipes.left_joins(:tags)
                           .group('recipes.id')
                           .order("COUNT(tags.id) #{sort_direction}")
      when 'title', 'servings', 'created_at'
        @recipes = @recipes.order(sort_column => sort_direction)
      else
        @recipes = @recipes.order(created_at: :desc)
      end
    else
      @recipes = @recipes.order(created_at: :desc)
    end
  end

  def show
    @recipe = Recipe.includes(:tags, recipe_ingredients: :ingredient, steps: []).find(params[:id])
  end

  def new
    @recipe = Recipe.new
  end

  def edit
  end

  def create
    @recipe = Recipe.new(recipe_params)

    if @recipe.save
      redirect_to @recipe, notice: "Recipe was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @recipe.update(recipe_params)
      redirect_to @recipe, notice: "Recipe was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle_favorite
    @recipe.update(favorite: !@recipe.favorite)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @recipe }
    end
  end

  def destroy
    @recipe.destroy!
    redirect_to recipes_url, notice: "Recipe was successfully deleted."
  end

  private
  def set_recipe
    @recipe = Recipe.find(params[:id])
  end

  def recipe_params
    params.require(:recipe).permit(:title, :description, :servings)
  end
end