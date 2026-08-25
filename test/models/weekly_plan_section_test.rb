require "test_helper"

class WeeklyPlanSectionTest < ActiveSupport::TestCase
  test "mark! updates status, updated_by, and status_changed_at" do
    section = WeeklyPlan.current_for(households(:one)).section("todos")
    user = users(:one)

    section.mark!("done", by: user)

    assert section.done?
    assert_equal user, section.updated_by
    assert_in_delta Time.current, section.status_changed_at, 2.seconds
  end

  test "status must be one of the known values" do
    section = WeeklyPlan.current_for(households(:one)).section("calendar")
    section.status = "bogus"
    refute section.valid?
  end
end
