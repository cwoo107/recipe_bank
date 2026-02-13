class IngredientsController < ApplicationController
  before_action :set_ingredient, only: %i[ show edit update destroy ]

  def index
    @ingredients = Ingredient.all
    @ingredient_families = [
      { color: 'mauve', label: 'Protein' },
      { color: 'mist', label: 'Vegetable' },
      { color: 'taupe', label: 'Fruit' },
      { color: 'honey', label: 'Grain' },
      { color: 'terracotta', label: 'Fat' }
    ]

    if params[:query].present?
      @ingredients = @ingredients.where('ingredient LIKE ? OR family LIKE ?',
                                "%#{params[:query]}%", "%#{params[:query]}%")
    end

    if params[:filter].present?
      @ingredients = @ingredients.where(family: params[:filter] )
    end

    @ingredients = @ingredients.order(:ingredient)
  end

  def show
    @ingredient = Ingredient.includes(:nutrition_fact, recipe_ingredients: :recipe).find(params[:id])
  end

  def new
    @ingredient = Ingredient.new
  end

  def edit
  end

  def create
  @ingredient = Ingredient.new(ingredient_params)

  if @ingredient.save
    redirect_to ingredients_path, notice: "Ingredient was successfully created."
  else
    render :new, status: :unprocessable_entity
  end
end

def update
  if @ingredient.update(ingredient_params)
    redirect_to ingredients_path, notice: "Ingredient was successfully updated."
  else
    render :edit, status: :unprocessable_entity
  end
end

  def destroy
    @ingredient.destroy!
    redirect_to ingredients_path, notice: "Ingredient was successfully deleted."
  end

  private
  def set_ingredient
    @ingredient = Ingredient.find(params[:id])
  end

  def ingredient_params
    params.expect(ingredient: [ :ingredient, :family, :brand, :organic, :unit_price, :unit_servings ])
  end
end