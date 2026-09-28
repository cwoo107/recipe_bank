require "test_helper"

class WeekStartDayTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Date.new(2026, 10, 7) # Wednesday
    @household = households(:one)
    sign_in users(:one) # alice, owner
  end

  test "an admin can change the week start day in household settings" do
    patch household_url, params: { household: { week_start_day: "0" } }

    assert_equal 0, @household.reload.week_start_day
    assert_redirected_to household_url
  end

  test "a limited member can't change the week start day" do
    sign_in users(:two) # bob, limited member

    patch household_url, params: { household: { week_start_day: "0" } }

    assert_equal 1, @household.reload.week_start_day
  end

  test "an invalid day is rejected" do
    patch household_url, params: { household: { week_start_day: "9" } }

    assert_equal 1, @household.reload.week_start_day
    assert_response :unprocessable_entity
  end

  test "the household page has a settings section with the week start picker for admins" do
    get household_url
    assert_select "#household_settings select[name='household[week_start_day]'] option[selected][value='1']", text: "Monday"
  end

  test "members see the household settings read-only" do
    sign_in users(:two) # bob, limited member

    get household_url
    assert_select "#household_settings form", count: 0
    assert_select "#household_settings dd", text: "Monday"
  end

  test "the old settings page redirects to the household page" do
    get edit_household_url
    assert_redirected_to household_url(anchor: "household_settings")
  end

  test "the meals page lays out the week from the household's start day" do
    @household.update!(week_start_day: 4)

    get meals_url
    assert_select "p", text: /week of Oct 01, 2026/

    # A mid-week date snaps back to that week's start.
    get meals_url(date: "2026-10-12")
    assert_select "p", text: /week of Oct 08, 2026/
  end

  test "the chore chart uses the household's start day" do
    @household.update!(week_start_day: 0)

    get weekly_chores_url
    assert_select "p", text: /Week of Oct 4, 2026/
  end

  test "the month view always starts on Sunday, whatever the household's week start" do
    @household.update!(week_start_day: 4)

    get month_calendars_url(year: 2026, month: 10)
    assert_select ".grid-cols-7 > div.uppercase", count: 7 do |headers|
      assert_equal %w[Sun Mon Tue Wed Thu Fri Sat], headers.map { |h| h.text.strip }
    end
    assert_select "[data-calendar-date]", minimum: 28 do |cells|
      assert_equal "2026-09-27", cells.first["data-calendar-date"], "Oct 1 2026 is a Thursday; the grid opens on the Sunday before"
    end
  end

  test "the week view still follows the household's week start" do
    @household.update!(week_start_day: 4)

    get week_calendars_url(date: "2026-10-07")
    assert_select "a[href='#{week_calendars_path(date: '2026-09-24')}']" # previous week starts on a Thursday
  end

  test "the week start is only applied for the request" do
    @household.update!(week_start_day: 0)
    get meals_url

    assert_equal :monday, Date.beginning_of_week
  end

  test "every week-based page renders with a non-Monday start" do
    @household.update!(week_start_day: 4)

    [ dashboard_url, plan_week_step_url(section: "chores", week: "2026-10-01"), meals_url, weekly_chores_url,
      grocery_lists_url, todos_url, week_calendars_url, month_calendars_url(year: 2026, month: 10) ].each do |url|
      get url
      assert_response :success, "expected #{url} to render"
    end
  end
end
