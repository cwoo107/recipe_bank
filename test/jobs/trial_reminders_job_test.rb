require "test_helper"

class TrialRemindersJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "emails the owner once per reminder" do
    household = households(:one)
    household.update!(trial_ends_at: 5.days.from_now)
    households(:two).update!(trial_ends_at: 20.days.from_now)

    assert_emails 1 do
      TrialRemindersJob.perform_now
    end
    email = ActionMailer::Base.deliveries.last
    assert_equal [ users(:one).email ], email.to
    assert_equal "Your HomemakersHaven trial ends in a week", email.subject
    assert_match "/household#billing", email.html_part.body.to_s
    assert_equal "week", household.reload.trial_reminder_sent

    assert_no_emails { TrialRemindersJob.perform_now }
  end

  test "tells the owner once the trial has ended" do
    households(:one).update!(trial_ends_at: 1.hour.ago, trial_reminder_sent: "day")

    assert_emails 1 do
      TrialRemindersJob.perform_now
    end
    assert_equal "Your HomemakersHaven trial has ended", ActionMailer::Base.deliveries.last.subject
  end
end
