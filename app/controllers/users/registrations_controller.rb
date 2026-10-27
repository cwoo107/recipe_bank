# Devise's sign-up, closed to the public until launch (Launch): until then
# the form only opens from a beta invite link (BetaInvitesController puts its
# token in the session), and the account it makes uses the invite up.
#
# Deleting an account needs "Delete Account" typed into its confirmation
# box (devise/registrations/edit) — see User::AccountDeletion for what goes.
class Users::RegistrationsController < Devise::RegistrationsController
  before_action :require_open_registrations_or_invite, only: %i[new create]

  def create
    super do |user|
      if user.persisted? && @beta_invite
        @beta_invite.redeem!(user)
        session.delete(:beta_invite_token)
      end
    end
  end

  def destroy
    unless params[:confirmation].to_s.strip == User::CONFIRMATION
      return redirect_to edit_user_registration_path, status: :see_other,
                         alert: "Type #{User::CONFIRMATION} to confirm deleting your account."
    end

    resource.delete_account!
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    set_flash_message! :notice, :destroyed
    redirect_to after_sign_out_path_for(resource_name), status: Devise.responder.redirect_status
  rescue Stripe::StripeError, StripeBilling::NotConfigured => error
    Rails.logger.error "Account deletion for user ##{resource.id} stopped: couldn't cancel the subscription (#{error.message})"
    redirect_to edit_user_registration_path, status: :see_other,
                alert: "We couldn't cancel your subscription, so your account wasn't deleted. Please try again, or contact us."
  end

  private

  def require_open_registrations_or_invite
    return if Launch.registrations_open?

    @beta_invite = BetaInvite.usable(session[:beta_invite_token])
    return if @beta_invite

    session.delete(:beta_invite_token)
    redirect_to root_path(anchor: "launch-list"),
                alert: "Sign-ups aren't open yet — join the list and we'll let you know when they are."
  end
end
