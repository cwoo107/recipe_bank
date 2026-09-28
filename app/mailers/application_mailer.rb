class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_SENDER", "HomemakersHaven <no-reply@example.com>")
  layout "mailer"
  helper :email
end
