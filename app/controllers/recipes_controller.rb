class RecipesController < ApplicationController
  before_action :set_recipe, only: %i[ show edit update destroy ]

  def index
    @recipes = Recipe.includes(:tags, :recipe_ingredients, :steps).all

    if params[:query].present?
      @recipes = @recipes.where('title LIKE ? OR description LIKE ?',
                                "%#{params[:query]}%", "%#{params[:query]}%")
    end

    if params[:filter].present?
      @recipes = @recipes.joins(:tags).where(tags: { id: params[:filter] })
    end

    @recipes = @recipes.order(created_at: :desc)
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