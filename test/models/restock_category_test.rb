require "test_helper"

class RestockCategoryTest < ActiveSupport::TestCase
  test "a new household gets the default categories, without Misc Supplies" do
    household = Household.create!(family_name: "New Household", owner: users(:one))

    assert_equal RestockCategory::DEFAULT_NAMES.sort, household.restock_categories.pluck(:name).sort
    assert_not_includes household.restock_categories.pluck(:name), "Misc Supplies"
  end

  test "requires a name unique within the household" do
    duplicate = RestockCategory.new(household: households(:one), name: "bathrooms")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "the same name is allowed in a different household" do
    category = RestockCategory.new(household: households(:two), name: "Bathrooms")
    assert category.valid?
  end

  test "deleting a category destroys its items" do
    category = restock_categories(:kitchen_one)
    item = households(:one).restock_items.create!(user: users(:one), name: "Sponges", restock_category: category)

    assert_difference("RestockItem.count", -1) do
      category.destroy
    end

    assert_raises(ActiveRecord::RecordNotFound) { item.reload }
  end
end
