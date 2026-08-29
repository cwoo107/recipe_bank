require "test_helper"

class RestockCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @category = restock_categories(:bathrooms_one) # household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should create restock category" do
    assert_difference("RestockCategory.count") do
      post restock_categories_url, params: { restock_category: { name: "Garage" } }
    end

    assert_equal households(:one), RestockCategory.last.household
  end

  test "should not create a duplicate list name within the household" do
    assert_no_difference("RestockCategory.count") do
      post restock_categories_url, params: { restock_category: { name: @category.name } }
    end
  end

  test "should rename restock category" do
    patch restock_category_url(@category), params: { restock_category: { name: "Half Bath" } }
    assert_redirected_to restock_items_url
    assert_equal "Half Bath", @category.reload.name
  end

  test "should destroy restock category and its items" do
    category = restock_categories(:kitchen_one) # no fixture items of its own
    item = households(:one).restock_items.create!(user: users(:one), name: "Sponges", restock_category: category)

    assert_difference([ "RestockCategory.count", "RestockItem.count" ], -1) do
      delete restock_category_url(category)
    end

    assert_raises(ActiveRecord::RecordNotFound) { item.reload }
  end

  test "a user in a different household cannot edit the category" do
    sign_in users(:three) # carol, household :two

    patch restock_category_url(@category), params: { restock_category: { name: "Should not work" } }
    assert_response :not_found
  end
end
