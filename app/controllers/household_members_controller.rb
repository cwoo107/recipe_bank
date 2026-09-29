class HouseholdMembersController < ApplicationController
  before_action :require_household!
  # Anyone in the household can view a member's summary; managing members is
  # admin-only.
  before_action :require_household_admin!, except: :show
  before_action :set_member, only: %i[show edit update destroy update_password send_password_reset]
  before_action :require_password_manageable!, only: %i[update_password send_password_reset]

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

    @weekly_chores = @member.weekly_chores.not_skipped.where(week_start: @date).includes(:chore).order(:scheduled_date, :position)
  end

  def new
    @member = current_household.household_members.new(color: current_household.next_member_color)
  end

  def create
    family_size_before = current_household.family_size
    @member = current_household.invite_member(**invite_params)

    if @member.persisted?
      # Listing someone beyond the family size bumps it (Household#grow_family_size_to_fit_members!).
      family_size_after = current_household.reload.family_size
      offer_family_size_adjustment(family_size_before, family_size_after) if family_size_after != family_size_before
      redirect_to household_path
    else
      @email = invite_params[:email]
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    email = params.dig(:household_member, :email).to_s.strip
    giving_login = email.present? && !@member.login?

    saved = @member.update(member_params)
    saved &&= current_household.give_login(@member, email:) if giving_login

    if saved
      notice = "#{@member.name} can now sign in — we emailed #{email} a link to set their password." if giving_login
      redirect_to household_path, notice:, status: :see_other
    else
      @email = email
      render :edit, status: :unprocessable_entity
    end
  end

  # An admin sets a new password for a member's login.
  def update_password
    user = @member.user
    if user.update(params.expect(user: [ :password, :password_confirmation ]))
      redirect_to household_path, notice: "#{@member.name}'s password was changed.", status: :see_other
    else
      @password_errors = user.errors.full_messages
      render :edit, status: :unprocessable_entity
    end
  end

  # Or emails them a link to choose a new one themselves.
  def send_password_reset
    @member.user.send_reset_password_instructions
    redirect_to household_path, notice: "We emailed #{@member.user.email} a link to reset their password.", status: :see_other
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
    params.expect(household_member: [:name, :email, :role, :color]).to_h.symbolize_keys
  end

  # A login's email belongs to its own account settings. Role only matters
  # for members with a login (or getting one now), and the owner is always
  # admin.
  def member_params
    permitted = params.expect(household_member: [:name, :role, :color])
    getting_login = params.dig(:household_member, :email).present?
    @member.owner? || !(@member.login? || getting_login) ? permitted.except(:role) : permitted
  end

  # Admins can reset another member's password — not the owner's (theirs is
  # managed from their own account), and not their own (use account settings).
  def require_password_manageable!
    return if helpers.password_manageable?(@member)

    redirect_to household_path, alert: "You can't change that password here.", status: :see_other
  end
end
