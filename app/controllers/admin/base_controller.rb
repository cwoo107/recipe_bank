# Staff pages for running the service — app admins only (users.app_admin,
# granted from the console, never the UI). Everyone else gets a 404, so the
# section doesn't advertise itself. Open whatever the admin's own household's
# billing state.
class Admin::BaseController < ApplicationController
  skip_before_action :require_active_subscription!
  before_action :require_app_admin!

  private

  def require_app_admin!
    raise ActiveRecord::RecordNotFound unless current_user&.app_admin?
  end
end
