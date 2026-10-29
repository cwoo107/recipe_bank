require "application_system_test_case"

# Manage Chores' Last done cell on desktop: Air Datepicker (date_field_controller)
# in an inline cell that saves on change.
class ChoreLastDonePickerTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  test "picking a day in the Last done cell saves it" do
    chore = chores(:one)
    chore.update!(last_completed_at: nil)
    login_as users(:one), scope: :user
    visit weekly_chores_url(view: "table")
    # date_field_controller has swapped in Air Datepicker (it loads from a CDN).
    assert_selector "#chore_#{chore.id}_inline_last_completed_at[readonly]", visible: :all

    within "##{ActionView::RecordIdentifier.dom_id(chore)}" do
      find("[data-inline-cell-target='display']", text: "Never").click
    end
    # The 1st, so it's never after today (disabled) whatever zone the browser's in.
    find(".air-datepicker-cell.-day-:not(.-other-month-)[data-date='1']").click

    first_of_month = Date.parse(page.evaluate_script("new Date().toDateString()")).beginning_of_month
    within "##{ActionView::RecordIdentifier.dom_id(chore)}" do
      assert_text first_of_month.strftime("%a, %b %-d")
    end
    assert_equal first_of_month, chore.reload.last_completed_at&.to_date
  end
end
