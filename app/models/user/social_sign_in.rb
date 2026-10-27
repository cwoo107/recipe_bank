# Signing in with Google or Apple (Users::OmniauthCallbacksController).
#
# A provider account we've seen before signs its user in. A new one whose
# verified email matches an existing account is linked to it; otherwise a
# new account can be made from it (when sign-ups allow — the controller
# decides). Those accounts get a random password they don't know, so they're
# marked awaiting_first_password: account settings won't ask for a current
# password until they've chosen one. They also start without a household —
# HouseholdSetupsController has them name it first.
module User::SocialSignIn
  extend ActiveSupport::Concern

  included do
    has_many :identities, dependent: :destroy
  end

  class_methods do
    # The account this provider sign-in belongs to, linking it by verified
    # email if need be — or nil when there's no such account yet.
    def from_omniauth(auth)
      identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
      return identity.user if identity

      email = omniauth_verified_email(auth)
      user = find_by(email:) if email
      user&.identities&.create!(provider: auth.provider, uid: auth.uid)
      user
    end

    # A new account for this provider sign-in. Raises if it can't be made —
    # e.g. no verified email, or one that's already taken.
    def create_from_omniauth!(auth)
      create!(email: omniauth_verified_email(auth),
              password: Devise.friendly_token(32),
              awaiting_first_password: true,
              skip_household_provisioning: true) do |user|
        user.identities.build(provider: auth.provider, uid: auth.uid)
      end
    end

    private

    # Google only fills info.email in when it's verified; Apple says so
    # with email_verified.
    def omniauth_verified_email(auth)
      email = auth.info.email.presence&.downcase
      email if email && auth.info.email_verified != false
    end
  end
end
