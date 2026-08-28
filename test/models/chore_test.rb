require "test_helper"

class ChoreTest < ActiveSupport::TestCase
  test "requires a name and a valid frequency" do
    chore = Chore.new(household: households(:one))
    refute chore.valid?
    assert_includes chore.errors[:name], "can't be blank"

    chore.name = "Vacuum"
    chore.frequency = "yearly" # not one of the allowed values
    refute chore.valid?
    assert_includes chore.errors[:frequency], "is not included in the list"
  end

  test "is due immediately when never completed" do
    chore = chores(:one)
    chore.update!(last_completed_at: nil)

    assert chore.due?
    assert_equal Date.current, chore.next_due_on
  end

  test "next_due_on adds the frequency's interval to the last completion" do
    chore = chores(:one) # weekly
    chore.update!(last_completed_at: Date.current)

    assert_equal Date.current + 1.week, chore.next_due_on
    refute chore.due?
    assert chore.due?(as_of: Date.current + 1.week)
  end

  test "frequency intervals cover every supported frequency" do
    expectations = {
      "weekly" => 1.week, "biweekly" => 2.weeks, "monthly" => 1.month,
      "quarterly" => 3.months, "semiannually" => 6.months, "annually" => 1.year
    }

    expectations.each do |frequency, interval|
      chore = chores(:one)
      chore.update!(frequency: frequency, last_completed_at: Date.current)
      assert_equal Date.current + interval, chore.next_due_on, "expected #{frequency} to add #{interval}"
    end
  end

  test "due_and_unscheduled excludes chores already on this week's list and chores not yet due" do
    household = households(:one)
    week_start = Date.current.beginning_of_week

    due_chore = chores(:one)
    due_chore.update!(last_completed_at: nil)

    not_due = household.chores.create!(name: "Wash windows", frequency: "quarterly", last_completed_at: Date.current)

    already_scheduled = household.chores.create!(name: "Mop floors", frequency: "weekly")
    household.weekly_chores.create!(chore: already_scheduled, week_start: week_start)

    due = Chore.due_and_unscheduled(household, week_start: week_start)

    assert_includes due, due_chore
    refute_includes due, not_due
    refute_includes due, already_scheduled
  end

  test "due_and_unscheduled excludes a recurring chore on its 'off' week (it's handled by auto-scheduling, not Due soon)" do
    household = households(:one)
    week_start = Date.current.beginning_of_week
    biweekly = household.chores.create!(name: "Mow lawn", frequency: "biweekly",
                                         default_weekday: (week_start + 2).wday, default_weekday_started_on: week_start)

    off_week = week_start + 7
    due = Chore.due_and_unscheduled(household, week_start: off_week)

    refute_includes due, biweekly
  end

  test "auto_schedule_recurring! replicates a due chore onto its remembered weekday" do
    household = households(:one)
    week_start = Date.current.beginning_of_week
    wednesday = week_start + 2
    chore = household.chores.create!(name: "Vacuum", frequency: "weekly", default_weekday: wednesday.wday)

    Chore.auto_schedule_recurring!(household, week_start: week_start)

    weekly_chore = household.weekly_chores.find_by(chore: chore, week_start: week_start)
    assert_not_nil weekly_chore
    assert_equal wednesday, weekly_chore.scheduled_date
  end

  test "auto_schedule_recurring! skips chores without a remembered weekday" do
    household = households(:one)
    week_start = Date.current.beginning_of_week
    chore = household.chores.create!(name: "Vacuum", frequency: "weekly") # never scheduled

    Chore.auto_schedule_recurring!(household, week_start: week_start)

    assert_nil household.weekly_chores.find_by(chore: chore, week_start: week_start)
  end

  test "auto_schedule_recurring! recurs a weekly chore regardless of completion status" do
    household = households(:one)
    week_start = Date.current.beginning_of_week
    # Just completed today -> would NOT be "due" by completion-based reckoning,
    # but weekly chores recur on schedule regardless of that.
    chore = household.chores.create!(name: "Take out trash", frequency: "weekly",
                                      default_weekday: (week_start + 2).wday, last_completed_at: Date.current)

    Chore.auto_schedule_recurring!(household, week_start: week_start)

    assert_not_nil household.weekly_chores.find_by(chore: chore, week_start: week_start)
  end

  test "auto_schedule_recurring! never processes a non-recurring frequency, even if default_weekday is somehow set" do
    household = households(:one)
    week_start = Date.current.beginning_of_week
    # Bypasses the normal callback path on purpose, to prove auto_schedule_recurring!
    # itself is the guard, not just the thing that sets default_weekday.
    chore = household.chores.create!(name: "Deep clean", frequency: "quarterly", default_weekday: (week_start + 2).wday)

    Chore.auto_schedule_recurring!(household, week_start: week_start)

    assert_nil household.weekly_chores.find_by(chore: chore, week_start: week_start)
  end

  test "auto_schedule_recurring! does not duplicate a chore already on the week's list" do
    household = households(:one)
    week_start = Date.current.beginning_of_week
    chore = household.chores.create!(name: "Vacuum", frequency: "weekly", default_weekday: (week_start + 2).wday)
    household.weekly_chores.create!(chore: chore, week_start: week_start, scheduled_date: week_start + 4)

    assert_no_difference("WeeklyChore.count") do
      Chore.auto_schedule_recurring!(household, week_start: week_start)
    end
  end

  test "auto_schedule_recurring! schedules a biweekly chore on its 'on' week and skips its 'off' week" do
    household = households(:one)
    anchor_week = Date.current.beginning_of_week
    chore = household.chores.create!(name: "Mow lawn", frequency: "biweekly",
                                      default_weekday: (anchor_week + 2).wday, default_weekday_started_on: anchor_week)

    Chore.auto_schedule_recurring!(household, week_start: anchor_week)
    assert_not_nil household.weekly_chores.find_by(chore: chore, week_start: anchor_week), "should schedule on the anchor week"

    off_week = anchor_week + 7
    Chore.auto_schedule_recurring!(household, week_start: off_week)
    assert_nil household.weekly_chores.find_by(chore: chore, week_start: off_week), "should skip the very next week"

    on_week = anchor_week + 14
    Chore.auto_schedule_recurring!(household, week_start: on_week)
    assert_not_nil household.weekly_chores.find_by(chore: chore, week_start: on_week), "should resume two weeks after the anchor"
  end

  test "biweekly_due_on_week? treats the anchor week and every second week after as 'on'" do
    anchor_week = Date.current.beginning_of_week
    chore = chores(:one)
    chore.update!(default_weekday_started_on: anchor_week)

    assert chore.biweekly_due_on_week?(anchor_week)
    refute chore.biweekly_due_on_week?(anchor_week + 7)
    assert chore.biweekly_due_on_week?(anchor_week + 14)
    refute chore.biweekly_due_on_week?(anchor_week + 21)
  end
end
