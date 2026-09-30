# Daily (config/schedule.yml): emails each trialing household's owner a week
# before the trial ends, the day before, and once it has — each at most
# once, and only the latest one due if a run was missed.
class TrialRemindersJob < ApplicationJob
  queue_as :default

  def perform
    return unless Household::Billing.enforced?

    Household.trialing.where(trial_ends_at: ..(Time.current + Household::Billing::TRIAL_REMINDERS.values.max))
             .includes(:owner).find_each do |household|
      stage = household.due_trial_reminder or next

      BillingMailer.trial_reminder(household, stage).deliver_now
      household.update_column(:trial_reminder_sent, stage)
    end
  end
end
