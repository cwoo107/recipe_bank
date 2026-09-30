# Preview at http://localhost:3000/rails/mailers/billing_mailer
class BillingMailerPreview < ActionMailer::Preview
  def trial_ends_in_a_week = BillingMailer.trial_reminder(Household.first, "week")
  def trial_ends_tomorrow  = BillingMailer.trial_reminder(Household.first, "day")
  def trial_ended          = BillingMailer.trial_reminder(Household.first, "ended")
  def payment_failed       = BillingMailer.payment_failed(Household.first)
end
