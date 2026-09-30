namespace :billing do
  # Run once on launch day, right before setting BILLING_ENFORCED=true, so
  # every household that hasn't picked a plan gets its full free month from
  # launch rather than from whenever it signed up.
  desc "Restart the free trial for every household still on it"
  task restart_trials: :environment do
    count = Household.trialing.update_all(trial_ends_at: Household::Billing::TRIAL_LENGTH.from_now, trial_reminder_sent: nil)
    puts "Restarted the trial for #{count} households (ends #{Household::Billing::TRIAL_LENGTH.from_now.to_date})."
  end
end
