class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_user_timezone
  helper_method :current_household, :active_weekly_plan
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

  # Every user is provisioned a household at signup (User#provision_household),
  # so this should always resolve — the fallback here just guards edge cases
  # (e.g. users created outside the normal signup path).
  def current_household
    @current_household ||= current_user&.household || provision_household_for(current_user)
  end

  # The in-progress weekly plan, if any — drives the sticky "continue
  # planning" bar shown from anywhere in the app. Suppressed on the wizard
  # itself and the dashboard, which already have their own continue/skip UI.
  def active_weekly_plan
    return nil unless user_signed_in?
    return nil if controller_name.in?(%w[plan_week dashboard])

    plan = WeeklyPlan.find_by(household: current_household, week_start: Date.current.beginning_of_week)
    plan&.currently_planning? ? plan : nil
  end

  def provision_household_for(user)
    return nil unless user

    user.create_owned_household!(family_name: Household.default_family_name_for(user))
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