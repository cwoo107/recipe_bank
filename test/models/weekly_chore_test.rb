require "test_helper"

class WeeklyChoreTest < ActiveSupport::TestCase
  test "defaults the assignee from the chore when none is given" do
    chore = chores(:one) # assigned to household_members(:one)
    weekly_chore = households(:one).weekly_chores.create!(chore: chore, week_start: Date.current.beginning_of_week)

    assert_equal chore.assignee, weekly_chore.assignee
  end

  test "first_available_day defaults to Monday when nothing is scheduled yet" do
    week_start = Date.current.beginning_of_week

    assert_equal week_start, WeeklyChore.first_available_day(households(:one), week_start)
  end

  test "first_available_day skips days that already have a chore" do
    week_start = Date.current.beginning_of_week
    other_chore = households(:one).chores.create!(name: "Vacuum", frequency: "weekly")
    households(:one).weekly_chores.create!(chore: other_chore, week_start: week_start, scheduled_date: week_start)

    assert_equal week_start + 1, WeeklyChore.first_available_day(households(:one), week_start)
  end

  test "first_available_day falls back to Monday once every day already has a chore" do
    week_start = Date.current.beginning_of_week
    (0..6).each do |i|
      chore = households(:one).chores.create!(name: "Chore #{i}", frequency: "weekly")
      households(:one).weekly_chores.create!(chore: chore, week_start: week_start, scheduled_date: week_start + i)
    end

    assert_equal week_start, WeeklyChore.first_available_day(households(:one), week_start)
  end

  test "only one instance of a chore can be on a given week's list" do
    chore = chores(:one)
    week_start = Date.current.beginning_of_week
    households(:one).weekly_chores.create!(chore: chore, week_start: week_start)

    duplicate = households(:one).weekly_chores.new(chore: chore, week_start: week_start)
    refute duplicate.valid?
  end

  test "mark_complete! stamps completed_at and updates the chore's last_completed_at" do
    chore = chores(:one)
    chore.update!(last_completed_at: nil)
    weekly_chore = households(:one).weekly_chores.create!(chore: chore, week_start: Date.current.beginning_of_week)

    weekly_chore.mark_complete!

    assert weekly_chore.completed?
    assert_not_nil weekly_chore.completed_at
    assert_in_delta Time.current, chore.reload.last_completed_at, 2.seconds
  end

  test "mark_incomplete! recomputes the chore's last_completed_at from remaining completions" do
    chore = chores(:one)
    chore.update!(last_completed_at: nil)

    older = households(:one).weekly_chores.create!(chore: chore, week_start: 2.weeks.ago.beginning_of_week)
    older.mark_complete!
    older.update!(completed_at: 2.weeks.ago)
    chore.update!(last_completed_at: 2.weeks.ago)

    newer = households(:one).weekly_chores.create!(chore: chore, week_start: Date.current.beginning_of_week)
    newer.mark_complete!
    assert_in_delta Time.current, chore.reload.last_completed_at, 2.seconds

    newer.mark_incomplete!

    refute newer.completed?
    assert_nil newer.completed_at
    assert_in_delta 2.weeks.ago, chore.reload.last_completed_at, 2.seconds
  end

  test "scheduled_date defaults to nil, sitting in the unscheduled column" do
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: Date.current.beginning_of_week)

    refute weekly_chore.scheduled?
  end

  test "scheduled_date must fall within the chore's own week" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.new(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 10)

    refute weekly_chore.valid?
    assert_includes weekly_chore.errors[:scheduled_date], "must fall within this chore's week"

    weekly_chore.scheduled_date = week_start + 3
    assert weekly_chore.valid?
  end

  test "move_to_day! schedules an unscheduled chore onto a day" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start)

    weekly_chore.move_to_day!(week_start + 2)

    assert_equal week_start + 2, weekly_chore.reload.scheduled_date
    assert weekly_chore.scheduled?
  end

  test "move_to_day! can move a chore back to unscheduled" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 2)

    weekly_chore.move_to_day!(nil)

    assert_nil weekly_chore.reload.scheduled_date
    refute weekly_chore.scheduled?
  end

  test "multiple chores can share the same scheduled_date" do
    week_start = Date.current.beginning_of_week
    other_chore = households(:one).chores.create!(name: "Vacuum", frequency: "weekly")

    a = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 1)
    b = households(:one).weekly_chores.create!(chore: other_chore, week_start: week_start, scheduled_date: week_start + 1)

    assert a.valid?
    assert b.valid?
  end

  test "scheduling onto a day remembers the chore's weekday for future weeks" do
    week_start = Date.current.beginning_of_week
    wednesday = week_start + 2
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: wednesday)

    assert_equal wednesday.wday, chores(:one).reload.default_weekday
  end

  test "rescheduling to a different day updates the remembered weekday" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 2)

    weekly_chore.move_to_day!(week_start + 4)

    assert_equal (week_start + 4).wday, chores(:one).reload.default_weekday
  end

  test "moving back to unscheduled clears the remembered weekday" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 2)

    weekly_chore.move_to_day!(nil)

    assert_nil chores(:one).reload.default_weekday
  end

  test "destroying a scheduled weekly chore clears the remembered weekday" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 2)
    assert_not_nil chores(:one).reload.default_weekday

    weekly_chore.destroy!

    assert_nil chores(:one).reload.default_weekday
  end

  test "destroying an unscheduled weekly chore does not touch the remembered weekday" do
    week_start = Date.current.beginning_of_week
    chores(:one).update!(default_weekday: 3)
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start + 7)

    weekly_chore.destroy!

    assert_equal 3, chores(:one).reload.default_weekday
  end

  test "rescheduling propagates the new day onto already-generated future weeks" do
    week_start = Date.current.beginning_of_week
    tuesday = week_start + 1
    thursday = week_start + 3

    this_week = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: tuesday)
    future_week_start = week_start + 7
    future_instance = households(:one).weekly_chores.create!(chore: chores(:one), week_start: future_week_start,
                                                               scheduled_date: future_week_start + 1) # also Tuesday

    this_week.move_to_day!(thursday)

    assert_equal future_week_start + 3, future_instance.reload.scheduled_date # now Thursday
  end

  test "rescheduling does not touch a future week's instance that's already completed" do
    week_start = Date.current.beginning_of_week
    this_week = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 1)

    future_week_start = week_start + 7
    future_instance = households(:one).weekly_chores.create!(chore: chores(:one), week_start: future_week_start,
                                                               scheduled_date: future_week_start + 1, completed: true)

    this_week.move_to_day!(week_start + 3)

    assert_equal future_week_start + 1, future_instance.reload.scheduled_date # untouched
  end

  test "unscheduling propagates to already-generated future weeks too" do
    week_start = Date.current.beginning_of_week
    this_week = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: week_start + 1)

    future_week_start = week_start + 7
    future_instance = households(:one).weekly_chores.create!(chore: chores(:one), week_start: future_week_start,
                                                               scheduled_date: future_week_start + 1)

    this_week.move_to_day!(nil)

    assert_nil future_instance.reload.scheduled_date
  end

  test "scheduling a monthly chore does NOT set a remembered weekday (not recurring)" do
    week_start = Date.current.beginning_of_week
    monthly = households(:one).chores.create!(name: "Deep clean", frequency: "monthly")

    households(:one).weekly_chores.create!(chore: monthly, week_start: week_start, scheduled_date: week_start + 2)

    assert_nil monthly.reload.default_weekday
    assert_nil monthly.reload.default_weekday_started_on
  end

  %w[quarterly semiannually annually].each do |freq|
    test "scheduling a #{freq} chore does NOT set a remembered weekday" do
      week_start = Date.current.beginning_of_week
      chore = households(:one).chores.create!(name: "Chore", frequency: freq)

      households(:one).weekly_chores.create!(chore: chore, week_start: week_start, scheduled_date: week_start + 2)

      assert_nil chore.reload.default_weekday
    end
  end

  test "scheduling a weekly or biweekly chore records the week as the recurrence anchor" do
    week_start = Date.current.beginning_of_week
    biweekly = households(:one).chores.create!(name: "Mow lawn", frequency: "biweekly")

    households(:one).weekly_chores.create!(chore: biweekly, week_start: week_start, scheduled_date: week_start + 2)

    assert_equal week_start, biweekly.reload.default_weekday_started_on
  end

  test "moving to a different weekday resets the recurrence anchor to the new week" do
    week1 = Date.current.beginning_of_week
    households(:one).weekly_chores.create!(chore: chores(:one), week_start: week1, scheduled_date: week1 + 1) # Tuesday
    assert_equal week1, chores(:one).reload.default_weekday_started_on

    week3 = week1 + 14
    households(:one).weekly_chores.create!(chore: chores(:one), week_start: week3, scheduled_date: week3 + 3) # Thursday

    assert_equal week3, chores(:one).reload.default_weekday_started_on
  end

  test "moving within the same weekday does not reset the recurrence anchor" do
    week_start = Date.current.beginning_of_week
    tuesday = week_start + 1
    weekly_chore = households(:one).weekly_chores.create!(chore: chores(:one), week_start: week_start, scheduled_date: tuesday)
    original_anchor = chores(:one).reload.default_weekday_started_on

    # A later week's instance scheduled onto the same weekday shouldn't disturb the anchor.
    later_week = week_start + 14
    households(:one).weekly_chores.create!(chore: chores(:one), week_start: later_week, scheduled_date: later_week + 1)

    assert_equal original_anchor, chores(:one).reload.default_weekday_started_on
  end
end
