class GroceryListsController < ApplicationController
  before_action :set_grocery_list, only: %i[ show edit update destroy ]

  # GET /grocery_lists or /grocery_lists.json
  def index
    @date = Date.today.beginning_of_week
    if params[:date].present?
      @date = Date.parse(params[:date])
    end
    @grocery_lists = GroceryList.where("week_of >= ?", @date).where('week_of < ?', @date + 7).includes(:meal).includes(:ingredient)
  end

  # GET /grocery_lists/1 or /grocery_lists/1.json
  def show
  end

  # GET /grocery_lists/new
  def new
    @grocery_list = GroceryList.new
  end

  # GET /grocery_lists/1/edit
  def edit
  end

  # POST /grocery_lists or /grocery_lists.json
  def create
    @grocery_list = GroceryList.new(grocery_list_params)

    respond_to do |format|
      if @grocery_list.save
        format.html { redirect_to @grocery_list, notice: "Grocery list was successfully created." }
        format.json { render :show, status: :created, location: @grocery_list }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @grocery_list.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /grocery_lists/1 or /grocery_lists/1.json
  def update
    respond_to do |format|
      if @grocery_list.update(grocery_list_params)
        format.html { redirect_to @grocery_list, notice: "Grocery list was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @grocery_list }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @grocery_list.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /grocery_lists/1 or /grocery_lists/1.json
  def destroy
    @grocery_list.destroy!

    respond_to do |format|
      format.html { redirect_to grocery_lists_path, notice: "Grocery list was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_grocery_list
      @grocery_list = GroceryList.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def grocery_list_params
      params.expect(grocery_list: [ :week_of, :ingredient_id, :meal_id, :units, :checked, :manually_adjusted ])
    end
end
