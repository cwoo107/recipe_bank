class MealsController < ApplicationController
  before_action :set_meal, only: %i[show edit update destroy]

  def index
    @date = week_start_from_params

    all_meals = current_household.meals
                            .where("date >= ?", @date)
                            .where("date < ?", @date + 7)
                            .includes(recipe: { recipe_ingredients: :ingredient })

    @calendar_meals = all_meals
                        .select(&:calendar_meal?)
                        .group_by { |m| [(m.date - @date).to_i, m.meal_name.downcase] }

    @extra_meals = all_meals
                     .select(&:extra_meal?)
                     .group_by { |m| m.meal_name.downcase }

    @week_stats = compute_week_stats(all_meals)
  end

  def show
  end

  def new
    @meal = Meal.new(date: params[:date].present? ? Date.parse(params[:date]) : nil,
                     meal_name: params[:meal_name].present? ? params[:meal_name] : nil)
  end

  def edit
  end

  def create
    @meal = current_household.meals.build(meal_params)
    @meal.user = current_user

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
    household = @meal.household
    @meal.destroy!
    @meal.broadcast_remove_to(household, "meals")

    respond_to do |format|
      format.html { redirect_to meals_path(date: week_start), notice: "Meal was successfully removed." }
      format.json { head :no_content }
    end
  end

  private

  def set_meal
    @meal = current_household.meals.find(params.expect(:id))
  end

  def week_start_from_params
    params[:date].present? ? Date.parse(params[:date]) : Time.zone.today.beginning_of_week
  end

  def meal_params
    params.expect(meal: [:recipe_id, :meal_name, :date, :servings])
  end

  def compute_week_stats(meals)
    total_protein  = 0.0
    total_carbs    = 0.0
    total_fat      = 0.0
    total_calories = 0.0
    total_cost     = 0.0
    meal_breakdown = []

    meals.each do |meal|
      p = meal.scaled_protein
      c = meal.scaled_carbs
      f = meal.scaled_fat
      cal = meal.scaled_calories
      cost = meal.total_cost

      total_protein  += p
      total_carbs    += c
      total_fat      += f
      total_calories += cal
      total_cost     += cost

      meal_breakdown << {
        name:          meal.recipe.title,
        meal_name:     meal.meal_name,
        servings:      meal.servings,
        protein:       p.round(1),
        carbs:         c.round(1),
        fat:           f.round(1),
        calories:      cal.round,
        cost:          cost.round(2),
        cal_per_serv:  meal.calories_per_serving,
        protein_per_serv: meal.protein_per_serving,
        carbs_per_serv:   meal.carbs_per_serving,
        fat_per_serv:     meal.fat_per_serving,
        cost_per_serv:    meal.cost_per_serving.round(2)
      }
    end

    per_serv_protein  = (total_protein  / 7.0).round(1)
    per_serv_carbs    = (total_carbs    / 7.0).round(1)
    per_serv_fat      = (total_fat      / 7.0).round(1)
    per_serv_calories = (total_calories / 7.0).round
    per_serv_cost     = (total_cost     / 7.0).round(2)

    {
      total_protein:  total_protein.round(1),
      total_carbs:    total_carbs.round(1),
      total_fat:      total_fat.round(1),
      total_calories: total_calories.round,
      total_cost:     total_cost.round(2),
      per_serv_protein:  per_serv_protein,
      per_serv_carbs:    per_serv_carbs,
      per_serv_fat:      per_serv_fat,
      per_serv_calories: per_serv_calories,
      per_serv_cost:     per_serv_cost,
      meal_count:     meals.count,
      chart_data: {
        labels: [
          "Protein #{total_protein.round(1)}g",
          "Carbs #{total_carbs.round(1)}g",
          "Fat #{total_fat.round(1)}g"
        ],
        datasets: [{
                     data: [total_protein.round(1), total_carbs.round(1), total_fat.round(1)],
                     backgroundColor: [
                       'oklch(71.1% 0.019 323.02)',
                       'oklch(85% 0.08 95)',
                       'oklch(75% 0.06 45)'
                     ],
                     borderWidth: 2
                   }]
      },
      meals: meal_breakdown
    }
  end
end