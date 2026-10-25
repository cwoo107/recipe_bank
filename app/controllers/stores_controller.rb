# The household's stores, managed from a dialog on the restock checklist (new
# ones can also be typed straight into an item's form). Everything renders
# inside the dialog's "stores" frame.
class StoresController < ApplicationController
  before_action :authenticate_user!
  before_action :require_household_admin!
  before_action :set_store, only: %i[update destroy]

  def index
    @stores = current_household.stores.ordered
    @store  = current_household.stores.new
  end

  def create
    @store = current_household.stores.new(store_params)
    if @store.save
      redirect_to stores_path, status: :see_other
    else
      @stores = current_household.stores.ordered
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @store.update(store_params)
      redirect_to stores_path, status: :see_other
    else
      @stores = current_household.stores.ordered
      @store_with_errors = @store
      @store = current_household.stores.new
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @store.destroy
    redirect_to stores_path, status: :see_other
  end

  private

  def set_store
    @store = current_household.stores.find(params[:id])
  end

  def store_params
    params.expect(store: [ :name ])
  end
end
