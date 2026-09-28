class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  around_action :use_time_zone
  around_action :use_household_week_start, if: :user_signed_in?
  helper_method :current_household, :active_weekly_plan, :household_admin?, :current_member
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

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:household_family_name])
  end

  # Pages show times in the household's zone, so everyone in it sees the same
  # day and time (and it matches what calendar syncing used). Until one's
  # saved, the first admin's browser zone becomes it; signed-out pages just
  # use the browser's zone.
  def use_time_zone(&block)
    adopt_browser_time_zone if user_signed_in?

    zone = (current_household&.time_zone.presence if user_signed_in?) || browser_time_zone
    Time.use_zone(ActiveSupport::TimeZone[zone.to_s] || Time.zone_default, &block)
  end

  def browser_time_zone
    name = cookies[:browser_timezone].to_s
    name if ActiveSupport::TimeZone[name]
  end

  def adopt_browser_time_zone
    household = current_household
    return unless household && household.time_zone.blank? && browser_time_zone && household_admin?

    household.update_column(:time_zone, browser_time_zone)
  end

  # Weeks everywhere (meals, chores, plans, calendar, grocery lists) start on
  # the household's chosen day. Setting Date.beginning_of_week for the
  # request — thread-local, like Time.zone — makes every plain
  # `beginning_of_week` / `end_of_week` call follow it.
  def use_household_week_start
    previous = Date.beginning_of_week
    Date.beginning_of_week = current_household&.week_start_symbol || previous
    yield
  ensure
    Date.beginning_of_week = previous
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
    return nil unless user_signed_in? && household_admin? # planning is admin-only
    return nil if controller_name.in?(%w[plan_week dashboard])

    WeeklyPlan.in_progress_for(current_household)
  end

  # Queues the household page's "adjust upcoming meals?" notice, if there are
  # any upcoming meals the new family size would change.
  def offer_family_size_adjustment(from, to)
    change = FamilySizeChange.new(current_household, from:, to:)
    flash[:family_size_change] = change.to_flash if change.any?
  end

  # Assignee ids arrive from forms — only accept members of this household.
  def scoped_assignee_params(permitted)
    return permitted unless permitted.key?(:assignee_id)

    permitted.merge(assignee_id: current_household.household_members.where(id: permitted[:assignee_id].presence).pick(:id))
  end

  def provision_household_for(user)
    return nil unless user

    user.create_owned_household!(family_name: Household.default_family_name_for(user))
  end

  def require_household!
    return if current_household

    redirect_to new_household_path, alert: "Set up your household first."
  end

  # ── Permissions ────────────────────────────────────────────────────────
  # Owners and admins can do everything. Limited members can look at the
  # household's recipes, meals, lists and calendar, add to-dos (assigned to
  # themselves), and tick off the to-dos and chores assigned to them — see
  # TodosController and WeeklyChoresController for those per-item rules.

  def household_admin?
    return @household_admin if defined?(@household_admin)

    @household_admin = current_household&.admin?(current_user) || false
  end

  # The signed-in user's own member row (owners have one too).
  def current_member
    @current_member ||= current_household&.household_members&.find_by(user_id: current_user&.id)
  end

  def require_household_admin!
    deny_access unless household_admin?
  end

  # Page requests go back where they came from with an explanation; the
  # boards' background fetches (drag-and-drop) just get a 403.
  def deny_access(message = "Only household admins can do that.")
    if request.format.html? || request.format.turbo_stream?
      redirect_back_or_to root_path, alert: message, status: :see_other
    else
      head :forbidden
    end
  end

end