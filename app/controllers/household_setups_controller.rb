# "Name your household": the first stop for accounts made with Google / Apple
# (which skip the sign-up form's household name), and for anyone else left
# without a household — ApplicationController#require_household_name! sends
# them here until they've named one.
class HouseholdSetupsController < ApplicationController
  skip_before_action :require_household_name!
  before_action :redirect_if_named
  layout "marketing"

  def new
    @household = current_user.household || current_user.build_owned_household
  end

  def create
    @household = current_user.household || current_user.build_owned_household
    @household.family_name = params.dig(:household, :family_name).to_s.strip

    if @household.save
      redirect_to dashboard_path, notice: "Welcome to #{@household.family_name}!", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_named
    redirect_to dashboard_path if current_household&.family_name.present?
  end
end
