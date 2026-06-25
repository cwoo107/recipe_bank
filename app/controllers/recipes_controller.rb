class RecipesController < ApplicationController
  before_action :set_recipe,        only: %i[show edit update destroy toggle_favorite]
  before_action :require_ownership!, only: %i[edit update destroy]

  def index
    @recipes = Recipe.visible_to(current_user)
                     .includes(:tags, :recipe_ingredients, :steps, :user_favorites)

    if params[:filter].present?
      tag = Tag.find_by(id: params[:filter])
      @recipes = @recipes.joins(:recipe_tags).where(recipe_tags: { tag_id: tag&.id })
    end

    if params[:query].present?
      @recipes = @recipes.where("title LIKE ?", "%#{params[:query]}%")
    end

    @recipes = apply_sort(@recipes)
  end

  def show
  end

  def new
    @recipe = current_user.recipes.build
  end

  def edit
  end

  def create
    @recipe = current_user.recipes.build(recipe_params)

    if @recipe.save
      redirect_to @recipe, notice: "Recipe was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @recipe.update(recipe_params)
      redirect_to @recipe, notice: "Recipe was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recipe.destroy!
    redirect_to recipes_path, notice: "Recipe was successfully deleted.", status: :see_other
  end

  def toggle_favorite
    favorite = current_user.user_favorites.find_by(recipe: @recipe)

    if favorite
      favorite.destroy!
    else
      current_user.user_favorites.create!(recipe: @recipe)
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "favorite_button_#{@recipe.id}",
          partial: "recipes/favorite_button",
          locals: { recipe: @recipe }
        )
      end
      format.html { redirect_to @recipe }
    end
  end

  private

  def set_recipe
    @recipe = Recipe.visible_to(current_user).find(params.expect(:id))
  end

  def require_ownership!
    unless @recipe.owned_by?(current_user)
      redirect_to recipes_path, alert: "You can only modify your own recipes."
    end
  end

  def apply_sort(scope)
    case params[:sort]
    when 'title'       then scope.order(title: sort_direction)
    when 'servings'    then scope.order(servings: sort_direction)
    when 'ingredients' then scope.left_joins(:recipe_ingredients)
                                 .group(:id)
                                 .order(Arel.sql("COUNT(recipe_ingredients.id) #{sort_direction.to_s.upcase}"))
    when 'steps'       then scope.left_joins(:steps)
                                 .group(:id)
                                 .order(Arel.sql("COUNT(steps.id) #{sort_direction.to_s.upcase}"))
    else                    scope.by_favorite_for(current_user)
    end
  end

  def sort_direction
    params[:direction] == 'desc' ? :desc : :asc
  end

  def recipe_params
    params.expect(recipe: [:title, :description, :servings, :visibility])
  end
end