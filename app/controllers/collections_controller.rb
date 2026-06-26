class CollectionsController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_collection, only: %i[show edit update destroy add_recipe_dropdown]
  before_action :require_ownership!, only: %i[edit update destroy]

  def index
    @collections = current_user.collections.includes(:recipes).order(created_at: :desc)
  end

  def show
    # Allow viewing public collections from other users
    @collection = Collection.visible_to(current_user).find(params[:id])
    @recipes = @collection.recipes.includes(:tags, :recipe_ingredients, :user_favorites)
  end

  def new
    @collection = current_user.collections.build
  end

  def edit
  end

  def create
    @collection = current_user.collections.build(collection_params)

    if @collection.save
      redirect_to @collection, notice: "Collection created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @collection.update(collection_params)
      redirect_to @collection, notice: "Collection updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    collection_dom_id = ActionView::RecordIdentifier.dom_id(@collection)
    @collection.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(collection_dom_id),
          turbo_stream.prepend("flash", partial: "shared/flash", locals: { notice: "Collection deleted." })
        ]
      end
      format.html { redirect_to collections_path, notice: "Collection deleted.", status: :see_other }
    end
  end

  # Renders the dropdown Turbo Frame for adding a specific recipe to collections
  def add_recipe_dropdown
    @recipe = Recipe.find(params[:recipe_id])
    @user_collections = current_user.collections.order(:title)
    @recipe_collection_ids = @recipe.collection_recipes
                                    .where(collection: @user_collections)
                                    .pluck(:collection_id)
    render partial: "collections/add_recipe_dropdown",
           locals: { collection: @collection, recipe: @recipe,
                     user_collections: @user_collections,
                     recipe_collection_ids: @recipe_collection_ids }
  end

  private

  def set_collection
    @collection = Collection.find(params[:id])
  end

  def require_ownership!
    unless @collection.owned_by?(current_user)
      redirect_to collections_path, alert: "You can only modify your own collections."
    end
  end

  def collection_params
    params.expect(collection: [:title, :public])
  end
end