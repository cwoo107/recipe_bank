# Free access for a household until a date (Household#comp!) — for friends,
# testers and goodwill. Destroy ends it now.
class Admin::CompsController < Admin::BaseController
  before_action :set_household

  def create
    until_date = Date.iso8601(params[:until].to_s) rescue nil
    return redirect_to(admin_household_path(@household), alert: "Pick a date in the future.", status: :see_other) unless until_date&.future?

    @household.comp!(until_date.end_of_day, admin: current_user, note: params[:note].presence)
    redirect_to admin_household_path(@household), notice: "Free access until #{I18n.l(until_date, format: :long)}.", status: :see_other
  end

  def destroy
    @household.comp!(nil, admin: current_user, note: params[:note].presence)
    redirect_to admin_household_path(@household), notice: "Free access ended.", status: :see_other
  end

  private

  def set_household
    @household = Household.find(params[:household_id])
  end
end
