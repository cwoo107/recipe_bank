class MealsController < ApplicationController
  before_action :set_meal, only: %i[show edit update destroy]

  def index
    @date = week_start_from_params

    all_meals = current_user.meals
                            .where("date >= ?", @date)
                            .where("date < ?", @date + 7)
                            .includes(:recipe)

    @calendar_meals = all_meals
                        .select(&:calendar_meal?)
                        .group_by { |m| [(m.date - @date).to_i, m.meal_name.downcase] }

    @extra_meals = all_meals
                     .select(&:extra_meal?)
                     .group_by { |m| m.meal_name.downcase }
  end

  def show
  end

  def new
    @meal = Meal.new(date: params[:date].present? ? Date.parse(params[:date]) : nil)
  end

  def edit
  end

  def create
    @meal = current_user.meals.build(meal_params)

    if @meal.extra_meal? && @meal.date.blank?
      @meal.date = Time.zone.today.beginning_of_week
    end

    @date = @meal.date.beginning_of_week

    respond_to do |format|
      if @meal.save
        format.html { redirect_to meals_path, notice: "Meal was successfully added." }
        format.json { render :show, status: :created, location: @meal }
        format.turbo_stream
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @meal.errors, status: :unprocessable_entity }
      end
    end
  end

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

  def destroy
    week_start = @meal.date.beginning_of_week
    @meal.destroy!
    @meal.broadcast_remove_to("meals")

    respond_to do |format|
      format.html { redirect_to meals_path(date: week_start), notice: "Meal was successfully removed." }
      format.json { head :no_content }
    end
  end

  private

  def set_meal
    @meal = current_user.meals.find(params.expect(:id))
  end

  def week_start_from_params
    params[:date].present? ? Date.parse(params[:date]) : Time.zone.today.beginning_of_week
  end

  def meal_params
    params.expect(meal: [:recipe_id, :meal_name, :date, :servings])
  end
end