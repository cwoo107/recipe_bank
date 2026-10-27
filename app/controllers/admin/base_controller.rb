# Staff pages for running the service — app admins only (users.app_admin,
# granted from the console, never the UI). Everyone else gets a 404, so the
# section doesn't advertise itself. Open whatever the admin's own household's
# billing state.
#
# These pages are always the admin's own, even while they're viewing the app
# as someone else (Impersonation) — and never read-only.
class Admin::BaseController < ApplicationController
  layout "admin"

  skip_around_action :read_only_while_impersonating
  skip_before_action :require_active_subscription!
  before_action :require_app_admin!

  def current_user
    true_user
  end

  private

  def require_app_admin!
    raise ActiveRecord::RecordNotFound unless true_user&.app_admin?
  end
end
