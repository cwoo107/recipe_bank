# Where Google and Apple send people back after sign-in (see
# User::SocialSignIn for how the account is found, linked or made).
#
# Making a new account follows the same rule as the sign-up form
# (Users::RegistrationsController): until launch, only with a beta invite
# link, which the new account then uses up.
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2 = sign_in_with_provider
  def apple         = sign_in_with_provider

  private

  def sign_in_with_provider
    auth = request.env["omniauth.auth"]
    provider = SocialSignIn.name_for(auth.provider)
    user = User.from_omniauth(auth) || sign_up_with(auth)
    return unless user

    user.remember_me = true # stay signed in, as the password form's "Remember me" would
    set_flash_message(:notice, :success, kind: provider) if is_navigational_format?
    sign_in_and_redirect user, event: :authentication
  rescue ActiveRecord::RecordInvalid
    redirect_to new_user_session_path,
                alert: "We couldn't create an account from your #{provider} sign-in. " \
                       "If you already have one with that email, sign in with your password."
  end

  # A new account, if sign-ups are open to this visitor — otherwise sends
  # them to the launch list and returns nil.
  def sign_up_with(auth)
    beta_invite = BetaInvite.usable(session[:beta_invite_token])
    unless Launch.registrations_open? || beta_invite
      redirect_to root_path(anchor: "launch-list"),
                  alert: "Sign-ups aren't open yet — join the list and we'll let you know when they are."
      return
    end

    User.create_from_omniauth!(auth).tap do |user|
      if beta_invite
        beta_invite.redeem!(user)
        session.delete(:beta_invite_token)
      end
    end
  end
end
