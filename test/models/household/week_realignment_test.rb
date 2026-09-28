require "test_helper"

class Household::WeekRealignmentTest < ActiveSupport::TestCase
  # Wednesday. Under the default Monday start, this week began Mon Oct 5.
  TODAY = Date.new(2026, 10, 7)

  setup do
    travel_to TODAY
    @household = households(:one)
    @chore = chores(:one)
  end

  test "defaults to Monday" do
    assert_equal 1, Household.new.week_start_day
    assert_equal :monday, @household.week_start_symbol
  end

  test "rejects days outside Sunday..Saturday" do
    @household.week_start_day = 7
    assert_not @household.valid?
  end

  test "ordered_wdays runs from the start day" do
    @household.week_start_day = 4
    assert_equal [ 4, 5, 6, 0, 1, 2, 3 ], @household.ordered_wdays
  end

  test "scheduled chores move into the new week containing their day" do
    monday = weekly_chore(week_start: Date.new(2026, 10, 5), scheduled_date: Date.new(2026, 10, 5))
    sunday = weekly_chore(week_start: Date.new(2026, 10, 5), scheduled_date: Date.new(2026, 10, 11),
                          chore: @household.chores.create!(name: "Sweep", frequency: "weekly"))

    @household.update!(week_start_day: 0)

    assert_equal Date.new(2026, 10, 4), monday.reload.week_start
    assert_equal Date.new(2026, 10, 11), sunday.reload.week_start
    assert_equal Date.new(2026, 10, 11), sunday.scheduled_date, "the chore's day never changes"
  end

  test "two instances of one chore landing in the same new week keep the earlier one" do
    first  = weekly_chore(week_start: Date.new(2026, 10, 5),  scheduled_date: Date.new(2026, 10, 11))
    second = weekly_chore(week_start: Date.new(2026, 10, 12), scheduled_date: Date.new(2026, 10, 12))

    @household.update!(week_start_day: 0)

    assert_equal Date.new(2026, 10, 11), first.reload.week_start
    assert_not WeeklyChore.exists?(second.id)
  end

  test "a completed instance wins over an incomplete one in the same new week" do
    first  = weekly_chore(week_start: Date.new(2026, 10, 5),  scheduled_date: Date.new(2026, 10, 11))
    second = weekly_chore(week_start: Date.new(2026, 10, 12), scheduled_date: Date.new(2026, 10, 12), completed: true)

    @household.update!(week_start_day: 0)

    assert_not WeeklyChore.exists?(first.id)
    assert_equal Date.new(2026, 10, 11), second.reload.week_start
  end

  test "weekly plans and grocery lists move to the new week sharing the most days" do
    this_week = @household.weekly_plans.create!(week_start: Date.new(2026, 10, 5))
    next_week = @household.weekly_plans.create!(week_start: Date.new(2026, 10, 12))
    groceries = @household.grocery_lists.create!(week_of: Date.new(2026, 10, 5), ingredient: ingredients(:one), user: users(:one))

    @household.update!(week_start_day: 0)

    assert_equal Date.new(2026, 10, 4), this_week.reload.week_start
    assert_equal Date.new(2026, 10, 11), next_week.reload.week_start
    assert_equal Date.new(2026, 10, 4), groceries.reload.week_of
  end

  test "moving to Thursday makes last week's plan this week's — it shares more of this week's days" do
    last_week = @household.weekly_plans.create!(week_start: Date.new(2026, 9, 28))
    this_week = @household.weekly_plans.create!(week_start: Date.new(2026, 10, 5))

    @household.update!(week_start_day: 4)

    # New current week is Thu Oct 1 – Wed Oct 7.
    assert_equal Date.new(2026, 10, 1), last_week.reload.week_start
    assert_equal Date.new(2026, 10, 8), this_week.reload.week_start
  end

  test "past weeks are left alone" do
    old_plan  = @household.weekly_plans.create!(week_start: Date.new(2026, 9, 14))
    old_chore = weekly_chore(week_start: Date.new(2026, 9, 14), scheduled_date: Date.new(2026, 9, 15))

    @household.update!(week_start_day: 0)

    assert_equal Date.new(2026, 9, 14), old_plan.reload.week_start
    assert_equal Date.new(2026, 9, 14), old_chore.reload.week_start
  end

  test "a biweekly chore keeps its every-other-week rhythm across the change" do
    biweekly = @household.chores.create!(name: "Mow", frequency: "biweekly", default_weekday: 3,
                                         default_weekday_started_on: Date.new(2026, 10, 5))

    @household.update!(week_start_day: 0)

    assert biweekly.biweekly_due_on_week?(Date.new(2026, 10, 4))
    assert_not biweekly.biweekly_due_on_week?(Date.new(2026, 10, 11))
    assert biweekly.biweekly_due_on_week?(Date.new(2026, 10, 18))
  end

  private

  def weekly_chore(week_start:, scheduled_date:, chore: @chore, completed: false)
    @household.weekly_chores.create!(chore:, week_start:, scheduled_date:, completed:)
  end
end
