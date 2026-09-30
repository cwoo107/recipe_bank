require "test_helper"

class Household::BillingTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @admin = users(:three).tap { |user| user.update!(app_admin: true) }
  end

  test "a new household starts a 30-day trial" do
    freeze_time do
      household = User.create!(email: "new@example.com", password: "password123").household

      assert_equal "trialing", household.subscription_status
      assert_equal 30.days.from_now, household.trial_ends_at
      assert household.on_trial?
      assert household.access_allowed?
      assert_equal 30, household.trial_days_left
    end
  end

  test "an expired trial locks the household" do
    @household.update!(trial_ends_at: 1.minute.ago)

    assert @household.trial_expired?
    assert_not @household.access_allowed?
    assert_equal 0, @household.trial_days_left
  end

  test "days left round up, so the last day reads 1" do
    @household.update!(trial_ends_at: 3.hours.from_now)
    assert_equal 1, @household.trial_days_left
  end

  test "active and past-due subscriptions have access; canceled ones don't" do
    @household.update!(trial_ends_at: 1.day.ago)

    %w[active past_due].each do |status|
      @household.subscription_status = status
      assert @household.access_allowed?, status
    end

    @household.subscription_status = "canceled"
    assert_not @household.access_allowed?
  end

  test "a comp grants access until it runs out" do
    @household.update!(trial_ends_at: 1.day.ago, comped_until: 1.week.from_now)
    assert @household.access_allowed?
    assert_not @household.needs_plan?

    @household.update!(comped_until: 1.minute.ago)
    assert_not @household.access_allowed?
  end

  test "plan maps the stored interval back to a plan key" do
    @household.plan_interval = "year"
    assert_equal "annual", @household.plan
    @household.plan_interval = "month"
    assert_equal "monthly", @household.plan
  end

  test "extending an expired trial counts from now, and is logged" do
    freeze_time do
      @household.update!(trial_ends_at: 10.days.ago, trial_reminder_sent: "ended")

      assert_difference -> { AdminAction.count } do
        @household.extend_trial!(by: 14.days, admin: @admin, note: "Asked nicely")
      end

      assert_equal 14.days.from_now, @household.trial_ends_at
      assert_nil @household.trial_reminder_sent
      action = AdminAction.last
      assert_equal [ "extend_trial", @household, @admin, "Asked nicely" ], [ action.action, action.household, action.admin, action.note ]
    end
  end

  test "extending a running trial adds to its end" do
    freeze_time do
      @household.update!(trial_ends_at: 5.days.from_now)
      @household.extend_trial!(by: 7.days, admin: @admin)
      assert_equal 12.days.from_now, @household.trial_ends_at
    end
  end

  test "only app admins can make admin changes" do
    assert_raises(ActiveRecord::RecordInvalid) { @household.comp!(1.year.from_now, admin: users(:one)) }
    assert_nil @household.reload.comped_until
  end

  test "reminders come due a week out, a day out and at the end — once each" do
    travel_to Time.zone.parse("2026-01-01 12:00")
    @household.update!(trial_ends_at: 10.days.from_now)
    assert_nil @household.due_trial_reminder

    travel 3.days
    assert_equal "week", @household.due_trial_reminder
    @household.trial_reminder_sent = "week"
    assert_nil @household.due_trial_reminder

    travel 6.days
    assert_equal "day", @household.due_trial_reminder

    # A missed run skips straight to the latest one due.
    travel 2.days
    assert_equal "ended", @household.due_trial_reminder
    @household.trial_reminder_sent = "ended"
    assert_nil @household.due_trial_reminder
  ensure
    travel_back
  end

  test "no reminders once a household is comped or has subscribed" do
    @household.update!(trial_ends_at: 1.day.ago, comped_until: 1.year.from_now)
    assert_nil @household.due_trial_reminder

    @household.update!(comped_until: nil, stripe_subscription_id: "sub_123")
    assert_nil @household.due_trial_reminder
  end

  test "each household is in exactly the scope its billing_state names" do
    now = Time.current
    states = {
      "on_trial"      => { trial_ends_at: now + 5.days },
      "trial_expired" => { trial_ends_at: now - 1.day },
      "paying"        => { trial_ends_at: now - 1.day, subscription_status: "active" },
      "comped"        => { trial_ends_at: now - 1.day, comped_until: now + 1.day },
      "lapsed"        => { trial_ends_at: now - 1.day, subscription_status: "canceled" }
    }

    states.each do |state, attributes|
      @household.update!(comped_until: nil, subscription_status: "trialing", **attributes)
      assert_equal state, @household.billing_state

      Household::Billing::BILLING_STATES.each do |scope|
        assert_equal scope == state, Household.public_send(scope).exists?(@household.id), "#{state} household in #{scope}?"
      end
    end
  end
end
