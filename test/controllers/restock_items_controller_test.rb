require "test_helper"

class RestockItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @item = restock_items(:one) # belongs to household :one (alice + bob)
    @category = restock_categories(:bathrooms_one)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get restock_items_url
    assert_response :success
  end

  test "should create restock item" do
    assert_difference("RestockItem.count") do
      post restock_items_url, params: { restock_item: { name: "Paper towels", restock_category_id: restock_categories(:kitchen_one).id } }
    end

    assert_equal households(:one), RestockItem.last.household
  end

  test "should update restock item" do
    patch restock_item_url(@item), params: { restock_item: { name: "Updated" } }
    assert_redirected_to restock_items_url
    assert_equal "Updated", @item.reload.name
  end

  test "should destroy restock item" do
    assert_difference("RestockItem.count", -1) do
      delete restock_item_url(@item)
    end
  end

  test "reorder updates positions within a list" do
    other = households(:one).restock_items.create!(user: users(:one), name: "Second", restock_category: @item.restock_category)

    post reorder_restock_items_url, params: { restock_category_id: @item.restock_category_id, order: [ other.id, @item.id ] }

    assert_equal 1, other.reload.position
    assert_equal 2, @item.reload.position
  end

  test "move relocates an item to a different list" do
    kitchen = restock_categories(:kitchen_one)
    post move_restock_item_url(@item), params: { restock_category_id: kitchen.id, position: 1 }

    assert_equal kitchen, @item.reload.restock_category
  end

  test "mark_stocked marks the item stocked" do
    patch mark_stocked_restock_item_url(@item)

    assert @item.reload.stocked?
    assert_not @item.restock?
  end

  test "mark_restock marks the item needing restock" do
    patch mark_restock_restock_item_url(@item)

    assert @item.reload.restock?
    assert_not @item.stocked?
  end

  test "another member of the same household can see and edit the item" do
    sign_in users(:two) # bob, also in household :one

    patch restock_item_url(@item), params: { restock_item: { name: "Bob edited this" } }
    assert_redirected_to restock_items_url
    assert_equal "Bob edited this", @item.reload.name
  end

  test "a user in a different household cannot edit the item" do
    sign_in users(:three) # carol, household :two

    patch restock_item_url(@item), params: { restock_item: { name: "Should not work" } }
    assert_response :not_found
  end
end
