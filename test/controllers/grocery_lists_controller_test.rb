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

  test "only offers category filters for categories on this week's list" do
    week = Date.current.beginning_of_week
    kale = households(:one).ingredients.create!(ingredient: "Filter kale", family: "produce")
    households(:one).ingredients.create!(ingredient: "Filter milk", family: "dairy") # not on the list
    households(:one).grocery_lists.create!(ingredient: kale, week_of: week, user: users(:one))

    # Still offered while another category is the filter.
    get grocery_lists_url(date: week, filter: "dairy")

    assert_select "a[href*='filter=produce']", 1
    assert_select "a[href*='filter=dairy']", 0
  end

  test "adding and removing lines updates that week's category filters live" do
    week = Date.current.beginning_of_week
    kale = households(:one).ingredients.create!(ingredient: "Live kale", family: "produce")
    stream = [ households(:one), "grocery_family_filters", week ]

    broadcasts = capture_turbo_stream_broadcasts(stream) do
      post create_grocery_list_url(format: :turbo_stream), params: { grocery_list: { ingredient_id: kale.id, week_of: week, units: 1 } }
    end
    assert_equal [ "replace" ], broadcasts.map { |b| b["action"] }
    assert_includes broadcasts.first.to_html, "filter=produce"

    line = GroceryList.find_by!(ingredient: kale, week_of: week)
    broadcasts = capture_turbo_stream_broadcasts(stream) do
      delete grocery_list_url(line, format: :turbo_stream)
    end
    # (The helper returns everything sent on the stream so far.)
    assert_equal [ "replace", "replace" ], broadcasts.map { |b| b["action"] }
    assert_not_includes broadcasts.last.to_html, "filter=produce"
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

  # ── Select all / Delete all checked items ──

  test "the list shows Select all, and Delete all checked items only once something's ticked" do
    get grocery_lists_url(date: @grocery_list.week_of)

    assert_select "form:not([hidden]) button", text: "Select all"
    assert_select "form[hidden] button", text: "Delete all checked items"
    assert_select "#grocery_list_#{@grocery_list.id} input[type=checkbox][data-grocery-checks-target=box]"

    @grocery_list.update!(checked: true)
    get grocery_lists_url(date: @grocery_list.week_of)

    assert_select "form:not([hidden]) button", text: "Delete all checked items"
    assert_select "form:not([hidden]) button", text: "Unselect all" # it's the only item
  end

  test "select all ticks off the week's items, and only this household's" do
    week = @grocery_list.week_of
    note = households(:one).grocery_lists.create!(note: "Candles", week_of: week, user: users(:one))
    next_week = households(:one).grocery_lists.create!(note: "Later", week_of: week + 7, user: users(:one))

    patch check_all_grocery_lists_url, params: { date: week }, headers: { "HTTP_REFERER" => grocery_lists_url(date: week) }

    assert_redirected_to grocery_lists_url(date: week)
    assert @grocery_list.reload.checked?
    assert note.reload.checked?
    assert_not next_week.reload.checked?
    assert_not grocery_lists(:two).reload.checked?

    patch check_all_grocery_lists_url, params: { date: week, checked: false }
    assert_not @grocery_list.reload.checked?
  end

  test "select all keeps to the category filter" do
    week = @grocery_list.week_of
    note = households(:one).grocery_lists.create!(note: "Candles", week_of: week, user: users(:one))

    patch check_all_grocery_lists_url, params: { date: week, filter: @grocery_list.ingredient.family }

    assert @grocery_list.reload.checked?
    assert_not note.reload.checked? # a note has no category
  end

  test "delete all checked items removes just the checked ones from the week" do
    week = @grocery_list.week_of
    @grocery_list.update!(checked: true)
    unchecked = households(:one).grocery_lists.create!(note: "Candles", week_of: week, user: users(:one))
    other_week = households(:one).grocery_lists.create!(note: "Later", week_of: week + 7, user: users(:one), checked: true)

    assert_difference("GroceryList.count", -1) do
      delete destroy_checked_grocery_lists_url, params: { date: week }
    end
    assert_not GroceryList.exists?(@grocery_list.id)
    assert GroceryList.exists?(unchecked.id)
    assert GroceryList.exists?(other_week.id)
    assert_equal "1 checked item removed from the list.", flash[:notice]
  end

  test "limited members can't select all or delete" do
    sign_in users(:two) # bob, a limited member of household :one
    @grocery_list.update!(checked: true)

    assert_no_difference("GroceryList.count") do
      delete destroy_checked_grocery_lists_url, params: { date: @grocery_list.week_of }
    end
    get grocery_lists_url(date: @grocery_list.week_of)
    assert_select "button", text: "Delete all checked items", count: 0
  end
end
