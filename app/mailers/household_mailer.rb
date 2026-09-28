# Emails about joining a household.
class HouseholdMailer < ApplicationMailer
  # Sent when an admin adds a member with an email (or gives an existing
  # member a login). The link is a Devise password-reset link, so it lets them
  # choose their first password; it lasts as long as Devise's
  # reset_password_within.
  def invitation(user, token, household:)
    @user       = user
    @household  = household
    @member     = user.household_membership
    @url        = edit_user_password_url(reset_password_token: token)
    @expires_in = Devise.reset_password_within

    mail to: user.email, subject: "You're invited to join #{household.display_name} on HomemakersHaven"
  end
end
