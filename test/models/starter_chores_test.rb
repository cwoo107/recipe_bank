require "test_helper"

# A new household's chore chart starts with a few chores (Chore::STARTERS),
# each in its default category.
class StarterChoresTest < ActiveSupport::TestCase
  test "a new household gets the starter chores, filed in their categories" do
    household = Household.create!(family_name: "New Household", owner: users(:one))

    assert_equal Chore::STARTERS.map { |starter| starter[:name] }.sort, household.chores.pluck(:name).sort
    Chore::STARTERS.each do |starter|
      chore = household.chores.find_by!(name: starter[:name])
      assert_equal starter[:frequency], chore.frequency
      assert_equal starter[:category], chore.chore_category.name
      assert_nil chore.assignee
    end
  end

  test "every starter's category is one of the defaults" do
    assert_empty Chore::STARTERS.map { |starter| starter[:category] } - ChoreCategory::DEFAULT_NAMES
  end
end
