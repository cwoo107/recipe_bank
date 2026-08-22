class HouseholdMembersController < ApplicationController
  before_action :require_household!
  before_action :require_household_admin!
  before_action :set_member, only: %i[edit update destroy]

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
    user = @member.user
    @member.destroy!
    user&.destroy! # sub-user logins exist only for the household

    redirect_to household_path, status: :see_other
  end

  private

  def set_member
    @member = current_household.household_members.find(params.expect(:id))
  end

  # :email isn't a HouseholdMember attribute — it's passed as a keyword to
  # Household#invite_member, which builds the Devise user.
  def invite_params
    params.expect(household_member: [:name, :email, :role]).to_h.symbolize_keys
  end

  # Email/password changes belong to the member's own Devise account settings.
  def member_params
    params.expect(household_member: [:name, :role])
  end
end