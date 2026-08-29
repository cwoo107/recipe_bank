class RestockCategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_restock_category, only: %i[edit update destroy]

  def new
    @restock_category = current_household.restock_categories.new
  end

  def create
    @restock_category = current_household.restock_categories.new(restock_category_params)

    if @restock_category.save
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
    if @restock_category.update(restock_category_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to restock_items_path }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @restock_category.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to restock_items_path }
    end
  end

  private

  def set_restock_category
    @restock_category = current_household.restock_categories.find(params[:id])
  end

  def restock_category_params
    params.require(:restock_category).permit(:name)
  end
end
