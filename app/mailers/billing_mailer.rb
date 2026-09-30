# Emails to a household's owner about its plan (see TrialRemindersJob).
class BillingMailer < ApplicationMailer
  SUBJECTS = {
    "week"  => "Your HomemakersHaven trial ends in a week",
    "day"   => "Your HomemakersHaven trial ends tomorrow",
    "ended" => "Your HomemakersHaven trial has ended"
  }.freeze

  # stage is one of Household::Billing::TRIAL_REMINDERS' keys.
  def trial_reminder(household, stage)
    @household = household
    @owner     = household.owner
    @stage     = stage
    @url       = household_url(anchor: "billing")

    mail to: @owner.email, subject: SUBJECTS.fetch(stage)
  end

  # A renewal charge didn't go through (invoice.payment_failed). Stripe keeps
  # retrying; the household keeps access while it does.
  def payment_failed(household)
    @household = household
    @owner     = household.owner
    @url       = household_url(anchor: "billing")

    mail to: @owner.email, subject: "Your HomemakersHaven payment didn't go through"
  end
end
