class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_user_timezone
  helper_method :current_household
  layout :resolve_layout

  def require_ownership!(record, owner_method: :user)
    owner = record.public_send(owner_method)
    unless owner == current_user
      redirect_to root_path, alert: "You don't have permission to do that."
    end
  end

  def require_ingredient_ownership!(ingredient)
    unless ingredient.editable_by?(current_user)
      redirect_to ingredients_path, alert: "You can only edit ingredients you created."
    end
  end

  private

  def resolve_layout
    devise_controller? ? "marketing" : "application"
  end

  def set_user_timezone
    timezone = cookies[:browser_timezone]
    if timezone.present?
      # ActiveSupport understands IANA timezone names like "America/Denver"
      Time.zone = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone.find_tzinfo(timezone) rescue Time.zone
    end
  end

  def current_household
    @current_household ||= current_user&.household
  end

  def require_household!
    return if current_household

    redirect_to new_household_path, alert: "Set up your household first."
  end

  def require_household_admin!
    return if current_household&.admin?(current_user)

    redirect_to root_path, alert: "You don't have permission to manage this household."
  end

end