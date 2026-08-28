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
    remove_upcoming = params[:remove_upcoming] == "1"
    removed_count = remove_upcoming ? @recurring_meal.upcoming_meals.destroy_all.size : 0

    @recurring_meal.destroy!

    notice = if remove_upcoming
      "Recurring meal removed, along with #{helpers.pluralize(removed_count, 'upcoming meal')}."
    else
      "Recurring meal removed. Meals it already created were left on the calendar."
    end
    redirect_to recurring_meals_path, notice: notice
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
