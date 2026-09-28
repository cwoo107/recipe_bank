class MealsController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!, except: %i[index show week_stats]
  before_action :set_meal, only: %i[show edit update destroy]

  def index
    @date = week_start_from_params
    RecurringMeal.materialize_household_week!(current_household, @date)

    all_meals = week_meals(@date)

    @calendar_meals = all_meals
                        .select(&:calendar_meal?)
                        .group_by { |m| [(m.date - @date).to_i, m.meal_name.downcase] }

    @extra_meals = all_meals
                     .select(&:extra_meal?)
                     .group_by { |m| m.meal_name.downcase }

    @week_stats = MealWeekStats.new(all_meals).to_h
    @person_stats_available = person_stats_available?(all_meals)
  end

  # The Week summary panel's body for one person (or the whole household) —
  # loaded into its turbo frame by the person switcher.
  def week_stats
    @date   = week_start_from_params
    @member = current_household.household_members.find_by(id: params[:member_id])
    meals   = week_meals(@date)

    @week_stats = MealWeekStats.new(meals, member: @member).to_h
    @person_stats_available = person_stats_available?(meals)
    render layout: false
  end

  def show
  end

  def new
    @meal = Meal.new(date: params[:date].present? ? Date.parse(params[:date]) : nil,
                     meal_name: params[:meal_name].present? ? params[:meal_name] : nil)
    @meal.servings = current_household.default_servings_for(date: @meal.date, meal_name: @meal.meal_name)
    @week_start = Date.parse(params[:week]).beginning_of_week if params[:week].present?
  end

  def edit
  end

  def create
    if recurring_requested?
      create_recurring_meal
    else
      create_single_meal
    end
  end

  def update
    eaters_before = @meal.eater_ids

    respond_to do |format|
      # Editing a meal that a recurring rule generated detaches it — the
      # rule keeps generating the other days normally, this one becomes a
      # standalone meal (see RecurringMeal#materialize_week!, which never
      # regenerates a date once its occurrence tombstone exists).
      if @meal.update(meal_params.merge(recurring_meal_id: nil, **eater_params(:meal)))
        # "Take them out of the shared meal's servings?" — answered in the form.
        drop_confirmed_shared_servings([ [ @meal, @meal.reload.eater_ids - eaters_before ] ])

        # Saved from the Edit modal on the meals page: refresh that page in
        # place so the card (and week stats) pick up the change.
        format.turbo_stream { render turbo_stream: turbo_stream.refresh } if turbo_frame_request?
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

  def create_single_meal
    @meal = current_household.meals.build(meal_params.merge(eater_params(:meal)))
    @meal.user = current_user
    if @meal.extra_meal? && @meal.date.blank?
      @meal.date = Time.zone.today.beginning_of_week
    end

    if meal_params[:servings].blank?
      @meal.servings = @meal.eater_ids.any? ? @meal.eater_ids.size : current_household.default_servings_for(date: @meal.date, meal_name: @meal.meal_name)
    end

    @date = @meal.date.beginning_of_week

    respond_to do |format|
      if @meal.save
        @adjusted_meals = drop_confirmed_shared_servings([ [ @meal, @meal.eater_ids ] ])
        format.html { redirect_to meals_path, notice: "Meal was successfully added." }
        format.json { render :show, status: :created, location: @meal }
        format.turbo_stream
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @meal.errors, status: :unprocessable_entity }
      end
    end
  end

  def create_recurring_meal
    recurring = recurring_creation_params[:recurring] || {}

    @recurring_meal = current_household.recurring_meals.build(
      user: current_user,
      recipe_id: recurring_creation_params[:recipe_id],
      meal_name: recurring_creation_params[:meal_name],
      servings: recurring_creation_params[:servings].presence,
      pattern_type: recurring[:pattern_type],
      interval_days: recurring[:interval_days],
      days_of_week: recurring[:days_of_week],
      start_date: recurring[:start_date],
      end_type: recurring[:end_type],
      end_date: recurring[:end_date],
      **eater_params(:meal)
    )
    @date = (@recurring_meal.start_date || Time.zone.today).beginning_of_week

    respond_to do |format|
      if @recurring_meal.save
        @created_meals = @recurring_meal.materialize_week!(@date)
        @adjusted_meals = drop_confirmed_shared_servings(@created_meals.map { |m| [ m, m.eater_ids ] })
        format.html { redirect_to meals_path(date: @date), notice: "Recurring meal added." }
        format.turbo_stream { render "meals/create_recurring" }
      else
        @meal = Meal.new(recurring_creation_params.slice(:recipe_id, :meal_name, :servings))
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def recurring_requested?
    params.dig(:meal, :recurring, :enabled) == "1"
  end

  def recurring_creation_params
    params.expect(meal: [:recipe_id, :meal_name, :servings,
                          recurring: [:pattern_type, :interval_days, :start_date, :end_type, :end_date,
                                      days_of_week: []]])
  end

  def set_meal
    @meal = current_household.meals.find(params.expect(:id))
  end

  def week_start_from_params
    (params[:date].present? ? Date.parse(params[:date]) : Time.zone.today).beginning_of_week
  end

  def meal_params
    params.expect(meal: [:recipe_id, :meal_name, :date, :servings])
  end

  # Optional "who's eating" — only household members count, and the field is
  # only in the form for households with more than one person, so a missing
  # param leaves existing assignments alone.
  def eater_params(scope)
    ids = params.dig(scope, :eater_ids)
    return {} if ids.nil?

    { eater_ids: current_household.household_members.where(id: Array(ids).compact_blank).ids }
  end

  # The meal form asks, before saving, whether to take newly assigned people
  # out of shared meals already planned in the same slot. A single meal sends
  # the shared meals said yes to (drop_shared_meal_ids); a recurring meal —
  # whose slots aren't known until it's saved — sends drop_shared=1 for all.
  # Returns the shared meals that changed.
  def drop_confirmed_shared_servings(assignments)
    adjustment = SharedServingsAdjustment.new(current_household, assignments)

    if params.dig(:meal, :drop_shared) == "1"
      adjustment.apply!
    elsif (ids = Array(params.dig(:meal, :drop_shared_meal_ids)).compact_blank).any?
      adjustment.apply!(only_ids: ids)
    else
      []
    end
  end

  def week_meals(week_start)
    current_household.meals
                     .where(date: week_start...(week_start + 7))
                     .includes(:meal_assignments, :eaters, :household, recipe: { recipe_ingredients: :ingredient })
  end

  # The person switcher in the Week summary only shows once someone's been
  # assigned a meal this week — until then everyone's share is identical.
  def person_stats_available?(meals)
    current_household.assignable? && meals.any?(&:assigned?)
  end

end
