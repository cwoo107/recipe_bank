# Devise's sign-up, closed to the public until launch (Launch): until then
# the form only opens from a beta invite link (BetaInvitesController puts its
# token in the session), and the account it makes uses the invite up.
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
