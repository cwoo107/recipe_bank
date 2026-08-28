class RecurringMealsController < ApplicationController
  before_action :set_recurring_meal, only: %i[edit update destroy]

  def index
    @recurring_meals = current_household.recurring_meals.includes(:recipe).order(:start_date)
  end

  def edit
  end

  def update
    if @recurring_meal.update(recurring_meal_params)
      redirect_to recurring_meals_path, notice: "Recurring meal updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recurring_meal.destroy!
    redirect_to recurring_meals_path, notice: "Recurring meal removed. Meals it already created were left on the calendar."
  end

  private

  def set_recurring_meal
    @recurring_meal = current_household.recurring_meals.find(params[:id])
  end

  def recurring_meal_params
    params.expect(recurring_meal: [:recipe_id, :meal_name, :servings, :pattern_type, :interval_days,
                                    :start_date, :end_type, :end_date, days_of_week: []])
  end
end
