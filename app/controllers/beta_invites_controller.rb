# Where a beta invite link lands (/beta/:token): remembers the invite and
# sends them on to the sign-up form, which is otherwise closed before launch
# (Users::RegistrationsController).
class BetaInvitesController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_active_subscription!

  def show
    if user_signed_in?
      redirect_to dashboard_path, notice: "You're already signed in."
    elsif BetaInvite.usable(params[:token])
      session[:beta_invite_token] = params[:token]
      redirect_to new_user_registration_path
    else
      redirect_to root_path, alert: "That invite link has already been used or isn't valid. Ask for a new one, or sign in if you've already made your account."
    end
  end
end
