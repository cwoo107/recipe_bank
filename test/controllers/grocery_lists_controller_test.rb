require "test_helper"

class GroceryListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @grocery_list = grocery_lists(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get grocery_lists_url
    assert_response :success
  end

  test "should get new" do
    get new_grocery_list_url
    assert_response :success
  end

  test "should create grocery_list" do
    assert_difference("GroceryList.count") do
      post create_grocery_list_url, params: { grocery_list: { checked: @grocery_list.checked, ingredient_id: @grocery_list.ingredient_id, manually_adjusted: @grocery_list.manually_adjusted, units: @grocery_list.units, week_of: @grocery_list.week_of } }
    end

    assert_equal households(:one), GroceryList.last.household
    assert_redirected_to grocery_list_url(GroceryList.last)
  end

  test "should show grocery_list" do
    get grocery_list_url(@grocery_list)
    assert_response :success
  end

  test "should get edit" do
    get edit_grocery_list_url(@grocery_list)
    assert_response :success
  end

  test "should update grocery_list" do
    patch grocery_list_url(@grocery_list), params: { grocery_list: { checked: @grocery_list.checked, ingredient_id: @grocery_list.ingredient_id, manually_adjusted: @grocery_list.manually_adjusted, units: @grocery_list.units, week_of: @grocery_list.week_of } }
    assert_redirected_to grocery_list_url(@grocery_list)
  end

  test "should destroy grocery_list" do
    assert_difference("GroceryList.count", -1) do
      delete grocery_list_url(@grocery_list)
    end

    assert_redirected_to grocery_lists_url
  end

  test "another member of the same household can see the grocery list" do
    sign_in users(:two) # bob, also in household :one

    get grocery_list_url(@grocery_list)
    assert_response :success
  end

  test "a user in a different household cannot see the grocery list" do
    sign_in users(:three) # carol, household :two

    get grocery_list_url(@grocery_list)
    assert_response :not_found
  end

  test "the subtotal is wired to follow the rows live" do
    week = Date.current.beginning_of_week
    rice = households(:one).ingredients.create!(ingredient: "Rice", unit_price: 2.5)
    households(:one).grocery_lists.create!(ingredient: rice, user: users(:one), week_of: week, units: 3)

    get grocery_lists_url(date: week.iso8601)

    assert_select "[data-controller=grocery-subtotal]" do
      # Added items are broadcast into #grocery_lists, above the subtotal.
      assert_select "#grocery_lists [data-grocery-subtotal-target=row][data-price='2.5'][data-units='3']"
      assert_select "[data-grocery-subtotal-target=total]", text: /\$\d+\.\d{2}/
    end
  end
end
