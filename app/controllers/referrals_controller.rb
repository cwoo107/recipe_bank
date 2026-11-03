# Where a household's share link lands (/r/:code): remembers whose link it
# was and sends them on to sign up (ReferralSignUp) — open even before
# launch, as a beta invite is.
class ReferralsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_active_subscription!

  def show
    if user_signed_in?
      redirect_to dashboard_path, notice: "You're already signed in."
    elsif Household.exists?(referral_code: params[:code].to_s.downcase)
      session[:referral_code] = params[:code].to_s.downcase
      redirect_to new_user_registration_path
    else
      redirect_to root_path, alert: "That share link isn't valid. Check it with whoever sent it to you."
    end
  end
end
