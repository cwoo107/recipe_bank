require "test_helper"

class FamilySizeChangeTest < ActionDispatch::IntegrationTest
  TODAY = Date.new(2026, 1, 7) # Wednesday; week began Mon Jan 5

  setup do
    travel_to TODAY
    @household = households(:one) # family size 3
    @bob = household_members(:one)
    sign_in users(:one)

    @tomorrow_dinner = meal("Dinner", TODAY + 1, servings: 3)
    @leftovers       = meal("Lunch", TODAY + 2, servings: 5) # planned bigger on purpose
    @snack           = meal("Snack", TODAY.beginning_of_week, servings: 3) # week-level
    @yesterday       = meal("Dinner", TODAY - 1, servings: 3)
    @bobs_breakfast  = meal("Breakfast", TODAY + 1, servings: 1, eaters: [ @bob ])
    @rule = @household.recurring_meals.create!(user: users(:one), recipe: recipes(:one), meal_name: "Breakfast",
                                               pattern_type: "interval", interval_days: 1, start_date: TODAY,
                                               end_type: "ongoing", servings: 3)
  end

  test "changing the family size in settings offers to adjust upcoming meals" do
    patch household_url, params: { household: { family_size: "4" } }
    follow_redirect!

    assert_select "#family_size_notice", text: /changed from 3 to 4/
    assert_select "#family_size_notice", text: /add 1 serving to 4 upcoming shared meals and 1 recurring meal/
    assert_select "#family_size_notice form[action='#{adjust_servings_household_path}'] input[name=from][value='3']"
  end

  test "adding a member that raises the family size offers it too" do
    @household.invite_member(name: "Kid") # 3 listed, still fits
    post household_members_url, params: { household_member: { name: "Baby", email: "" } }
    follow_redirect!

    assert_select "#family_size_notice", text: /changed from 3 to 4/
  end

  test "no notice when the family size doesn't change" do
    patch household_url, params: { household: { family_name: "Does" } }
    follow_redirect!
    assert_select "#family_size_notice", count: 0
  end

  test "yes shifts upcoming shared meals and recurring meals by the difference" do
    patch adjust_servings_household_url, params: { from: 3, to: 4 }

    assert_equal 4, @tomorrow_dinner.reload[:servings]
    assert_equal 6, @leftovers.reload[:servings], "keeps its extra"
    assert_equal 4, @snack.reload[:servings]
    assert_equal 4, @rule.reload.servings
    assert_equal 3, @yesterday.reload[:servings], "past meals stay as eaten"
    assert_equal 1, @bobs_breakfast.reload[:servings], "assigned meals don't depend on family size"
  end

  test "a smaller family takes servings off, never below 1" do
    tiny = meal("Dinner", TODAY + 3, servings: 1)
    patch adjust_servings_household_url, params: { from: 3, to: 2 }

    assert_equal 2, @tomorrow_dinner.reload[:servings]
    assert_equal 1, tiny.reload[:servings]
  end

  test "limited members can't adjust meals" do
    sign_in users(:two) # bob
    patch adjust_servings_household_url, params: { from: 3, to: 4 }
    assert_equal 3, @tomorrow_dinner.reload[:servings]
  end

  private

  def meal(name, date, servings:, eaters: [])
    @household.meals.create!(recipe: recipes(:one), user: users(:one), meal_name: name, date:, servings:, eater_ids: eaters.map(&:id))
  end
end
