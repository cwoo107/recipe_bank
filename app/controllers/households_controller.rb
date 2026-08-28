# Each user has exactly one household, so this is now a singular resource:
# /household instead of /households/:id. No more Household.all or find(params[:id]).
class HouseholdsController < ApplicationController
  before_action :require_household!,       only: %i[show edit update destroy]
  before_action :set_household,            only: %i[show edit update destroy]
  before_action :require_household_admin!, only: %i[edit update]
  before_action :require_owner!,           only: :destroy

  def show
    @members = @household.household_members.includes(:user).order(:name)
  end

  def new
    redirect_to household_path and return if current_household

    @household = current_user.build_owned_household
  end

  def create
    redirect_to household_path and return if current_household

    @household = current_user.build_owned_household(household_params)

    if @household.save
      redirect_to household_path, notice: "Household created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @household.update(household_params)
      redirect_to household_path, notice: "Household updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @household.destroy!
    redirect_to root_path, notice: "Household deleted.", status: :see_other
  end

  private

  def set_household
    @household = current_household
  end

  def require_owner!
    return if @household.owner?(current_user)

    redirect_to household_path, alert: "Only the account owner can do that."
  end

  def household_params
    params.expect(household: [:family_name, :minutes_per_day])
  end
end