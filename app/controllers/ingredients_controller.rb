class IngredientsController < ApplicationController
  before_action :set_ingredient, only: %i[show edit update destroy]
  before_action :require_edit_permission!, only: %i[edit update destroy]

  def index
    @ingredient_families = [
      { color: 'mauve',      label: 'Protein' },
      { color: 'mist',       label: 'Produce' },
      { color: 'taupe',      label: 'Dairy' },
      { color: 'honey',      label: 'Grain' },
      { color: 'terracotta', label: 'Fat' },
      { color: 'mist',       label: 'Spices' }
    ]

    @ingredients = Ingredient.all.includes(:nutrition_fact)

    if params[:filter].present?
      @ingredients = @ingredients.where(family: params[:filter])
    end

    if params[:query].present?
      @ingredients = @ingredients.where("ingredient LIKE ?", "%#{params[:query]}%")
    end

    @ingredients = apply_sort(@ingredients)
  end

  def show
  end

  def new
    @ingredient = Ingredient.new
  end

  def edit
  end

  def create
    @ingredient = Ingredient.new(ingredient_params)
    @ingredient.created_by = current_user

    if @ingredient.save
      @recipe = Recipe.find(params[:recipe_id]) if params[:recipe_id].present?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [turbo_stream.replace("new_ingredient", partial: "recipes/new_ingredient")]
        end
        format.html { redirect_to @ingredient, notice: "Ingredient was successfully created." }
      end
    else

      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @ingredient.update(ingredient_params)
      redirect_to @ingredient, notice: "Ingredient was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    ingredient_dom_id = "ingredient_#{@ingredient.id}"
    @ingredient.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(ingredient_dom_id),
          turbo_stream.replace("ingredient", "<turbo-frame id='ingredient'></turbo-frame>"),
          turbo_stream.prepend("flash", partial: "shared/flash", locals: { notice: "Ingredient deleted." })
        ]
      end
      format.html { redirect_to ingredients_path, notice: "Ingredient was successfully deleted.", status: :see_other }
    end
  end

  private

  def set_ingredient
    @ingredient = Ingredient.find(params.expect(:id))
  end

  def require_edit_permission!
    require_ingredient_ownership!(@ingredient)
  end

  def apply_sort(scope)
    direction = params[:direction] == 'desc' ? :desc : :asc
    case params[:sort]
    when 'ingredient' then scope.order(ingredient: direction)
    when 'brand'      then scope.order(brand: direction)
    when 'family'     then scope.order(family: direction)
    when 'organic'    then scope.order(organic: direction)
    else scope.order(favorite: :desc, ingredient: :asc)
    end
  end

  def ingredient_params
    params.expect(ingredient: [:ingredient, :brand, :family, :organic, :favorite, :unit_price, :unit_servings])
  end
end