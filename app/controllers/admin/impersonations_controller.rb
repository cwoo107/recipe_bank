# Start and stop viewing the app as someone, read-only (see Impersonation).
# Both are logged in the admin history.
class Admin::ImpersonationsController < Admin::BaseController
  def create
    user = User.find(params[:user_id])

    if user.app_admin? || user.deleted_users_placeholder?
      redirect_to admin_user_path(user), alert: "You can't view the app as another admin.", status: :see_other
    else
      start_impersonating(user, note: params[:note].presence)
      redirect_to dashboard_path, notice: "Viewing as #{user.email} — read-only.", status: :see_other
    end
  end

  def destroy
    user = stop_impersonating
    redirect_to(user ? admin_user_path(user) : admin_root_path, status: :see_other)
  end
end
