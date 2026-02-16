class IngredientsController < ApplicationController
  before_action :set_ingredient, only: %i[ show edit update toggle_favorite destroy ]

  def index
    @ingredients = Ingredient.all
    @ingredient_families = [
      { color: 'mauve', label: 'Protein' },
      { color: 'mist', label: 'Produce' },
      { color: 'taupe', label: 'Dairy' },
      { color: 'honey', label: 'Grain' },
      { color: 'terracotta', label: 'Fat' },
      { color: 'mist', label: 'Spices' }
    ]

    if params[:query].present?
      @ingredients = @ingredients.where('ingredient LIKE ? OR family LIKE ?',
                                "%#{params[:query]}%", "%#{params[:query]}%")
    end

    if params[:filter].present?
      @ingredients = @ingredients.where(family: params[:filter] )
    end

    if params[:sort].present?
      sort_column = params[:sort]
      sort_direction = params[:direction] == 'desc' ? :desc : :asc
      @ingredients = @ingredients.order(sort_column => sort_direction)
    else
      @ingredients = @ingredients.order(:ingredient)
    end
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

  def toggle_favorite
    @ingredient.update(favorite: !@ingredient.favorite)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @ingredient }
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