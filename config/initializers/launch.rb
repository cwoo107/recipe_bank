# Before launch, public sign-up is closed: the home page says "Coming soon"
# and collects emails for the launch list, and only a beta invite link
# (BetaInvite) opens the sign-up form. Set REGISTRATIONS_OPEN=true to launch.
module Launch
  def self.registrations_open?
    Rails.application.config.x.registrations_open
  end
end

Rails.application.config.x.registrations_open = ENV["REGISTRATIONS_OPEN"] == "true"
