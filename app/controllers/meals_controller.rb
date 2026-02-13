class MealsController < ApplicationController
  before_action :set_meal, only: %i[ show edit update destroy ]

  # GET /meals or /meals.json
  def index
    @date = Date.today.beginning_of_week
    if params[:date].present?
      @date = Date.parse(params[:date])
    end
    @meals = Meal.where("date >= ?", @date).where('date < ?', @date + 7).includes(:recipe)
  end

  # GET /meals/1 or /meals/1.json
  def show
  end

  # GET /meals/new
  def new
    @meal = Meal.new
  end

  # GET /meals/1/edit
  def edit
  end

  # POST /meals or /meals.json
  def create
    @meal = Meal.new(meal_params)
    @date = @meal.date.beginning_of_week  # Calculate the week this meal belongs to

    respond_to do |format|
      if @meal.save
        # Manually broadcast with the correct @date context
        @meal.broadcast_append_to(
          "meals",
          target: "meals",
          partial: "meals/meal",
          locals: { meal: @meal, date: @date }
        )

        format.html { redirect_to meals_path, notice: "Meal was successfully added." }
        format.json { render :show, status: :created, location: @meal }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_meal", partial: "meals/new", locals: { meal: Meal.new }) }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @meal.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /meals/1 or /meals/1.json
  def update
    respond_to do |format|
      if @meal.update(meal_params)
        format.html { redirect_to @meal, notice: "Meal was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @meal }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @meal.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /meals/1 or /meals/1.json
  def destroy
    @meal = Meal.find(params[:id])
    week_start = @meal.date.beginning_of_week
    @meal.destroy

    @meal.broadcast_remove_to("meals")

    respond_to do |format|
      format.html { redirect_to meals_path, notice: "Meal was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_meal
      @meal = Meal.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def meal_params
      params.expect(meal: [ :recipe_id, :meal_name, :date ])
    end
end
