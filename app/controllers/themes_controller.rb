# The light / dark / system switch on the marketing site. Visitors' choice
# is kept in a cookie; a signed-in user's is saved to their account too (it's
# also on Account settings, via PreferencesController). The switch applies
# the theme in the page itself (theme_controller.js) — this just remembers it.
class ThemesController < ApplicationController
  skip_before_action :authenticate_user!, :require_active_subscription!

  def update
    theme = params[:theme].presence_in(User::THEMES)
    return head :unprocessable_entity unless theme

    cookies.permanent[:theme] = theme
    current_user.update!(theme:) if user_signed_in?

    respond_to do |format|
      format.html { redirect_back_or_to root_path, status: :see_other }
      format.json { head :no_content }
    end
  end
end
