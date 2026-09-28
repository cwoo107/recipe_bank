class RestockItemsController < ApplicationController
  before_action :authenticate_user!
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!, except: :index
  before_action :set_restock_item, only: %i[edit update destroy mark_stocked mark_restock]

  def index
    @categories = current_household.restock_categories.ordered
  end

  def new
    @restock_item = current_household.restock_items.new(restock_category_id: params[:restock_category_id] || current_household.restock_categories.ordered.first&.id)
  end

  def create
    @restock_item = current_household.restock_items.new(restock_item_params)
    @restock_item.user = current_user

    if @restock_item.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to restock_items_path }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @restock_item.update(restock_item_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to restock_items_path }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @restock_item.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("restock_item_#{@restock_item.id}") }
      format.html { redirect_to restock_items_path }
    end
  end

  # POST /restock_items/reorder
  # Params: { restock_category_id: "3", order: ["1","4","2"] }
  def reorder
    restock_category_id = params[:restock_category_id]
    return head :bad_request unless current_household.restock_categories.exists?(id: restock_category_id)

    Array(params[:order]).each_with_index do |id, index|
      current_household.restock_items
                  .where(restock_category_id: restock_category_id, id: id)
                  .update_all(position: index + 1)
    end

    head :ok
  end

  # POST /restock_items/:id/move
  # Params: { restock_category_id: "5", position: 2 }
  def move
    set_restock_item
    new_restock_category_id = params[:restock_category_id]
    return head :bad_request unless current_household.restock_categories.exists?(id: new_restock_category_id)

    @restock_item.move_to_list!(new_restock_category_id, params[:position])

    head :ok
  end

  def mark_stocked
    @restock_item.mark_stocked!
    respond_to do |format|
      format.turbo_stream { render shopping_list_context? ? :shopping_item : :update }
      format.html { redirect_to restock_items_path }
    end
  end

  def mark_restock
    @restock_item.mark_restock!
    respond_to do |format|
      format.turbo_stream { render shopping_list_context? ? :shopping_item : :update }
      format.html { redirect_to restock_items_path }
    end
  end

  private

  # Checking items off the restock shopping list (grocery list page) reuses
  # these actions but re-renders the shopping row instead of the checklist card.
  def shopping_list_context?
    params[:context] == "shopping"
  end

  def set_restock_item
    @restock_item = current_household.restock_items.find(params[:id])
  end

  def restock_item_params
    params.require(:restock_item).permit(:name, :brand, :store, :restock_category_id)
  end
end
