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

  test "an admin in the same household can see and edit the item" do
    household_members(:one).update!(role: :admin)
    sign_in users(:two) # bob, now an admin in household :one

    patch restock_item_url(@item), params: { restock_item: { name: "Bob edited this" } }
    assert_redirected_to restock_items_url
    assert_equal "Bob edited this", @item.reload.name
  end

  test "a user in a different household cannot edit the item" do
    sign_in users(:three) # carol, household :two

    patch restock_item_url(@item), params: { restock_item: { name: "Should not work" } }
    assert_response :not_found
  end

  test "the card shows when the item was last restocked, and the form can set it" do
    patch restock_item_url(@item), params: { restock_item: { last_restocked: "2025-09-14" } }
    assert_equal Date.new(2025, 9, 14), @item.reload.last_restocked

    get restock_items_url
    assert_select "#restock_item_#{@item.id}", text: /Last restocked Sep 14, 2025/
  end

  test "ticking an item off the shopping list dates last_restocked; the card's buttons don't" do
    patch mark_restock_restock_item_url(@item), as: :turbo_stream
    patch mark_stocked_restock_item_url(@item), as: :turbo_stream
    assert_nil @item.reload.last_restocked

    @item.update!(last_restocked: Date.new(2025, 9, 14))
    patch mark_restock_restock_item_url(@item), as: :turbo_stream
    patch mark_stocked_restock_item_url(@item), params: { context: "shopping" }, as: :turbo_stream
    assert_equal Date.current, @item.reload.last_restocked

    # Unticking it straight away puts back the date it replaced.
    assert_select "input[name=previous_restocked][value='2025-09-14']"
    patch mark_restock_restock_item_url(@item), params: { context: "shopping", previous_restocked: "2025-09-14" }, as: :turbo_stream
    assert_equal Date.new(2025, 9, 14), @item.reload.last_restocked
    assert @item.restock?
  end

  test "unticking a first-ever restock clears the date again" do
    @item.mark_restock!
    patch mark_stocked_restock_item_url(@item), params: { context: "shopping" }, as: :turbo_stream
    assert_select "input[name=previous_restocked][value='']"

    patch mark_restock_restock_item_url(@item), params: { context: "shopping", previous_restocked: "" }, as: :turbo_stream
    assert_nil @item.reload.last_restocked
  end

  test "adding an item clears the form it came from, keeping its list" do
    kitchen = restock_categories(:kitchen_one)

    post restock_items_url, params: { restock_item: { name: "Sponges", brand: "Scotch-Brite", restock_category_id: kitchen.id } },
                            headers: { "Turbo-Frame" => "new_restock_item_#{kitchen.id}" }, as: :turbo_stream

    assert_match %(<turbo-stream action="prepend" target="restock_items_#{kitchen.id}">), response.body
    assert_select "turbo-stream[action=replace][target=new_restock_item_#{kitchen.id}]" do
      assert_select "template" do |template|
        form = Nokogiri::HTML.fragment(template.first.inner_html)
        assert_equal "", form.at("input[name='restock_item[name]']")["value"].to_s
        assert_nil form.at("input[name='restock_item[brand]']")["value"]
        assert_equal kitchen.id.to_s, form.at("select[name='restock_item[restock_category_id]'] option[selected]")["value"]
      end
    end
  end
end
