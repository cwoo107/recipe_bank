require "application_system_test_case"

# The recurring meal form's start date picker (shared/_recurrence_fields):
# the week picker, also highlighting each later date the rule lands on.
class RecurringMealStartPickerTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  setup do
    @rule = recurring_meals(:one)
    @rule.update!(pattern_type: "interval", interval_days: 2, start_date: Date.new(2026, 1, 5), end_type: "ongoing")
    login_as users(:one), scope: :user
  end

  test "highlights the dates the rule repeats on, following the form" do
    visit edit_recurring_meal_url(@rule)
    assert_text "Select a starting date"

    # Every other day from Monday the 5th.
    assert_selector "button[data-date='2026-01-05'][aria-pressed='true']"
    assert_repeats "2026-01-07", "2026-01-09"
    assert_no_selector "button[data-date='2026-01-06'][data-repeats]"

    find("label", text: "Every Day").click
    assert_repeats "2026-01-06", "2026-01-07"

    # The rule already had Sundays ticked.
    choose "Specific weekdays", allow_label_click: true
    assert_repeats "2026-01-11"
    find("label", text: "Sun").click
    find("label", text: "Wed").click
    assert_repeats "2026-01-07"
    assert_no_selector "button[data-date='2026-01-11'][data-repeats]"
    assert_no_selector "button[data-date='2026-01-06'][data-repeats]"

    # A later start date: nothing before it, and the 7th is now the start.
    find("button[data-date='2026-01-07']").click
    assert_selector "button[data-date='2026-01-07'][aria-pressed='true']"
    assert_no_selector "button[data-repeats]"

    click_button "Next week"
    assert_repeats "2026-01-14"

    choose "End of this week", allow_label_click: true
    assert_no_selector "button[data-repeats]"
  end

  private

  def assert_repeats(*dates)
    dates.each { |date| assert_selector "button[data-date='#{date}'][data-repeats]" }
  end
end
