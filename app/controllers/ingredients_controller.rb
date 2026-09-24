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
    @recipe     = recipe_from_params

    # Coming from a recipe, the form also collects the line for that recipe.
    @recipe_ingredient = @recipe.recipe_ingredients.build if @recipe
  end

  def edit
  end

  def create
    @ingredient = Ingredient.new(ingredient_params)
    @ingredient.created_by = current_user
    @recipe = recipe_from_params

    return create_and_add_to_recipe if @recipe

    if @ingredient.save
      enrich_later(@ingredient)

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

  # "Create and add Ingredient": the ingredient and its line on the recipe are
  # saved together, then the slow parts (cost, serving size, nutrition) are
  # estimated in the background so the user isn't left waiting on the AI.
  def create_and_add_to_recipe
    @recipe_ingredient = @recipe.recipe_ingredients.build(
      recipe_ingredient_params.merge(ingredient: @ingredient)
    )

    saved = ActiveRecord::Base.transaction do
      @ingredient.save && @recipe_ingredient.save
    rescue ActiveRecord::RecordInvalid
      false
    end

    unless saved
      return render :new, status: :unprocessable_entity
    end

    enrich_later(@ingredient)

    respond_to do |format|
      # Submitted from the recipe page, where this form was loaded into the
      # "new_ingredient" frame: stream the new line in and hand the frame back
      # to the ingredient picker, rather than navigating away.
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("recipe_ingredients_section",
                               partial: "recipes/recipe_ingredients", locals: { recipe: @recipe }),
          turbo_stream.replace("new_ingredient", partial: "recipes/new_ingredient"),
          turbo_stream.replace("macros_chart",
                               partial: "recipes/macros_chart", locals: { recipe: @recipe })
        ]
      end
      format.html do
        redirect_to @recipe,
                    notice: "Added #{@ingredient.ingredient}. We're estimating its cost and nutrition now."
      end
    end
  end

  # Only the owner can add ingredients to a recipe, matching what the recipe
  # page actually offers.
  def recipe_from_params
    return nil if params[:recipe_id].blank?

    current_user.recipes.find(params[:recipe_id])
  end

  def recipe_ingredient_params
    return {} if params[:recipe_ingredient].blank?

    params.expect(recipe_ingredient: [:quantity, :unit])
  end

  def enrich_later(ingredient)
    IngredientEnrichmentJob.perform_later(ingredient.id)
  end

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