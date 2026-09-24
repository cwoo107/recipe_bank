class RecipesController < ApplicationController
  before_action :set_recipe,        only: %i[show edit update destroy toggle_favorite toggle_visibility]
  before_action :require_ownership!, only: %i[edit update destroy toggle_visibility]

  # Sizes the visibility toggle can round-trip — it posts its own size back so
  # the replacement matches wherever it was rendered, and that lands in a CSS
  # class, so only these are accepted.
  ICON_SIZES = %w[size-4 size-5 size-6 size-7].freeze

  # The two lists behind the Recipes tab: what the household has, and the
  # public pool they can pull from.
  SCOPES = %w[household public].freeze

  def index
    @scope   = SCOPES.include?(params[:scope]) ? params[:scope] : "household"
    @recipes = scoped_recipes.includes(:tags, :recipe_ingredients, :steps, :user_favorites)

    if params[:filter].present?
      tag = Tag.find_by(id: params[:filter])
      @recipes = @recipes.joins(:recipe_tags).where(recipe_tags: { tag_id: tag&.id })
    end

    if params[:query].present?
      @recipes = @recipes.where("title LIKE ?", "%#{params[:query]}%")
    end

    @recipes = apply_sort(@recipes)

    # Lets the browse list show "Saved" instead of offering a second copy.
    @saved_source_ids = saved_source_ids_for(@recipes) if @scope == "public"
  end

  def show
    # Only relevant for recipes from outside the household — drives the
    # "Save to Our Recipes" button vs. a link to the copy they already have.
    unless @recipe.owned_by_household?(current_household)
      @saved_copy = Recipe.for_household(current_household).find_by(source_recipe: @recipe)
    end
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
    saved = @recipe.update(recipe_params)

    respond_to do |format|
      # The show page's inline title/description fields post to .turbo_stream
      # and get just the read-only halves back, so the form they're still
      # typing in isn't yanked out from under them.
      format.turbo_stream do
        if saved
          render turbo_stream: [
            turbo_stream.replace("recipe_title", partial: "recipes/title", locals: { recipe: @recipe }),
            turbo_stream.replace("recipe_description", partial: "recipes/description", locals: { recipe: @recipe })
          ]
        else
          render turbo_stream: turbo_stream.replace("recipe_heading", partial: "recipes/heading", locals: { recipe: @recipe }),
                 status: :unprocessable_entity
        end
      end

      format.html do
        if saved
          redirect_to @recipe, notice: "Recipe was successfully updated.", status: :see_other
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    @recipe.destroy!
    redirect_to recipes_path, notice: "Recipe was successfully deleted.", status: :see_other
  end

  # Forks one of the household's own recipes so a variant can be built from it
  # — a beef version of the chicken bowls — without retyping the whole thing.
  # Public recipes from elsewhere go through #save_to_household instead.
  def duplicate
    source = Recipe.for_household(current_household).find(params.expect(:id))
    copy   = source.duplicate_for(current_user, title: source.copy_title_for(current_user))

    redirect_to copy, notice: "Copied \"#{source.title}\". Make it your own."
  end

  # Copies a public recipe into the household (it becomes the current user's,
  # which is what makes it show up under "Our Recipes").
  def save_to_household
    source = Recipe.publicly_visible.find(params.expect(:id))

    if source.owned_by_household?(current_household)
      return redirect_back fallback_location: recipes_path(scope: "public"),
                           notice: "That recipe is already one of yours."
    end

    existing = Recipe.for_household(current_household).find_by(source_recipe: source)
    if existing
      return redirect_to existing, notice: "Your household already saved this recipe."
    end

    copy = source.duplicate_for(current_user)
    redirect_to copy, notice: "Saved to your recipes."
  end

  # Flips the recipe between public and private in place, the same way the
  # favourite star toggles.
  def toggle_visibility
    @recipe.update!(visibility: @recipe.public? ? "private" : "public")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "visibility_button_#{@recipe.id}",
          partial: "recipes/visibility_icon",
          locals: { recipe: @recipe, size: icon_size }
        )
      end
      format.html { redirect_to @recipe }
    end
  end

  # Drag-and-drop over the instruction list, which mixes this recipe's own
  # steps with the component recipes sitting in it. Items arrive as
  # "step-12" / "component-4" because ids alone wouldn't say which is which.
  def reorder_instructions
    recipe = current_user.recipes.find(params[:id])

    Array(params[:order]).each_with_index do |token, index|
      type, id = token.to_s.split("-", 2)

      case type
      when "step"      then recipe.steps.where(id: id).update_all(instruction_position: index + 1)
      when "component" then recipe.recipe_components.where(id: id).update_all(instruction_position: index + 1)
      end
    end

    head :ok
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
    @recipe = Recipe.browsable_by_household(current_household).find(params.expect(:id))
  end

  def icon_size
    ICON_SIZES.include?(params[:size]) ? params[:size] : "size-5"
  end

  def scoped_recipes
    if @scope == "public"
      Recipe.public_beyond_household(current_household)
    else
      Recipe.for_household(current_household)
    end
  end

  def saved_source_ids_for(recipes)
    Recipe.for_household(current_household)
          .where(source_recipe_id: recipes.map(&:id))
          .pluck(:source_recipe_id)
          .to_set
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