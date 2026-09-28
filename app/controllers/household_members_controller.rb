class HouseholdMembersController < ApplicationController
  before_action :require_household!
  # Anyone in the household can view a member's summary; managing members is
  # admin-only.
  before_action :require_household_admin!, except: :show
  before_action :set_member, only: %i[show edit update destroy]

  # A member's week: their share of meals (calories, macros, cost), plus the
  # to-dos and chores assigned to them.
  def show
    @date = (params[:date].present? ? Date.parse(params[:date]) : Date.current).beginning_of_week
    week  = @date...(@date + 7)

    meals = current_household.meals.where(date: week)
                             .includes(:meal_assignments, :household, recipe: { recipe_ingredients: :ingredient })
                             .order(:date)
    @meal_stats = MealWeekStats.new(meals, member: @member).to_h

    @todos_done = @member.todos.where(status: "done", end_date: @date.beginning_of_day..(@date + 6).end_of_day).order(:end_date)
    @todos_open = @member.todos.where.not(status: "done").order(:status, :position)

    @weekly_chores = @member.weekly_chores.where(week_start: @date).includes(:chore).order(:scheduled_date, :position)
  end

  def new
    @member = current_household.household_members.new
  end

  def create
    @member = current_household.invite_member(**invite_params)

    if @member.persisted?
      redirect_to household_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @member.update(member_params)
      redirect_to household_path, status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @member.owner?
      return redirect_to household_path, alert: "The owner can't be removed from their household.", status: :see_other
    end

    current_household.remove_member!(@member)
    redirect_to household_path, notice: "#{@member.name} was removed.", status: :see_other
  end

  private

  def set_member
    @member = current_household.household_members.find(params.expect(:id))
  end

  # :email isn't a HouseholdMember attribute — it's passed as a keyword to
  # Household#invite_member, which builds the Devise user (or, left blank,
  # adds a member with no login).
  def invite_params
    params.expect(household_member: [:name, :email, :role]).to_h.symbolize_keys
  end

  # Email/password changes belong to the member's own Devise account settings.
  # Role only matters for members with a login, and the owner is always admin.
  def member_params
    permitted = params.expect(household_member: [:name, :role])
    @member.owner? || !@member.login? ? permitted.except(:role) : permitted
  end
end
