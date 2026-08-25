require "test_helper"

class CalendarSourceTest < ActiveSupport::TestCase
  test "position is scoped to household, shared across members" do
    household = households(:one)

    first = household.calendar_sources.create!(user: users(:one), name: "Alice's second calendar", provider: "google", color: "olive")

    assert_equal 2, first.reload.position # calendar_sources(:one) already occupies position 1
  end
end
