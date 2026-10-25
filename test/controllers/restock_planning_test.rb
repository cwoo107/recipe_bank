require "test_helper"

class RestockPlanningTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @bathrooms = restock_categories(:bathrooms_one)
    @kitchen   = restock_categories(:kitchen_one)
    @toilet_paper = restock_items(:one) # Costco, Bathrooms
    sign_in users(:one)
  end

  # ── Plan your week ──

  test "the restock checklist is a wizard step between meals and the grocery list" do
    assert_equal %w[meals restock groceries], Dashboard.section_keys.first(3)

    patch plan_week_step_url(section: "meals"), params: { status: "done" }
    assert_redirected_to plan_week_step_url(section: "restock", week: Date.current.beginning_of_week)
  end

  test "the restock step shows the checklist so items can be checked in place" do
    get plan_week_step_url(section: "restock")

    assert_response :success
    assert_select "#restock_category_#{@bathrooms.id}"
    assert_select "#restock_item_#{@toilet_paper.id} form[action='#{mark_restock_restock_item_path(@toilet_paper)}']"
    assert_select "p", text: /1 not checked yet this week/
  end

  test "the restock step counts as planned once something's been checked this week" do
    section = Dashboard::RestockSection.new(household: @household, week_start: Date.current.beginning_of_week,
                                            weekly_plan: WeeklyPlan.current_for(@household))
    assert section.empty?

    @toilet_paper.mark_restock!
    section = Dashboard::RestockSection.new(household: @household.reload, week_start: Date.current.beginning_of_week,
                                            weekly_plan: WeeklyPlan.current_for(@household))
    assert_not section.empty?
    assert_equal "1 item to restock", section.summary_line
  end

  # ── Restock shopping list ──

  test "the restock list groups items marked Restock by store, then category" do
    @toilet_paper.mark_restock!
    soap   = restock("Dish soap", @kitchen, store: "costco ") # same store, different casing/spacing
    wipes  = restock("Wipes", @bathrooms, store: "Target")
    salt   = restock("Salt", @kitchen, store: "")
    restock("Paper towels", @kitchen, store: "Costco", marked: false)

    assert_equal 2, @household.stores.count

    list = RestockItem.shopping_list(@household)

    assert_equal [ "Costco", "Target", "Any store" ], list.map(&:first)
    costco = list.first.last
    assert_equal [ [ @bathrooms, [ @toilet_paper ] ], [ @kitchen, [ soap ] ] ], costco
    assert_equal [ [ @bathrooms, [ wipes ] ] ], list.second.last
    assert_equal [ [ @kitchen, [ salt ] ] ], list.third.last
  end

  test "an item at several stores is listed once, under the store with the most on the list" do
    3.times { |n| restock("Amazon thing #{n}", @kitchen, store: "Amazon") }
    restock("Target thing", @kitchen, store: "Target")
    batteries = restock("Batteries", @kitchen, store: "Target, Amazon")

    list = RestockItem.shopping_list(@household).to_h
    assert_includes list["Amazon"].to_h[@kitchen], batteries
    assert_not_includes list["Target"].to_h[@kitchen], batteries

    get grocery_lists_url(list: "restock")
    assert_select ".shopping_restock_item_#{batteries.id}", 1
  end

  test "a tie between stores goes to the one first alphabetically" do
    sponges = restock("Sponges", @kitchen, store: "Target, Costco")

    list = RestockItem.shopping_list(@household).to_h # toilet paper isn't marked, so 1 each
    assert_equal [ sponges ], list["Costco"].to_h[@kitchen]
    assert_nil list["Target"]
  end

  test "ticking an item off re-renders it by class" do
    sponges = restock("Sponges", @kitchen, store: "Costco")

    patch mark_stocked_restock_item_url(sponges), params: { context: "shopping" }, as: :turbo_stream
    assert_match(/turbo-stream action="replace" targets=".shopping_restock_item_#{sponges.id}"/, response.body)
  end

  # ── Stores ──

  test "an item's stores are picked by name, adding new ones to the household's list" do
    patch restock_item_url(@toilet_paper), params: { restock_item: { store_names: "costco, Target" } }

    assert_equal [ "Costco", "Target" ], @toilet_paper.reload.stores.map(&:name)
    assert_equal [ "Costco", "Target" ], @household.stores.ordered.map(&:name)
  end

  test "the stores dialog renames and deletes the household's stores" do
    costco = stores(:costco_one)
    get stores_url
    assert_select "turbo-frame#stores input[value=Costco]"

    patch store_url(costco), params: { store: { name: "Costco Wholesale" } }
    assert_equal "Costco Wholesale", costco.reload.name

    assert_difference("RestockItemStore.count", -1) { delete store_url(costco) }
    assert @toilet_paper.reload.persisted?
  end

  private

  def restock(name, category, store:, marked: true)
    item = @household.restock_items.create!(name:, restock_category: category, store_names: store, user: users(:one))
    item.mark_restock! if marked
    item
  end
end
