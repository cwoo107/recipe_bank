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

    list = RestockItem.shopping_list(@household)

    assert_equal [ "Costco", "Target", "Any store" ], list.map(&:first)
    costco = list.first.last
    assert_equal [ [ @bathrooms, [ @toilet_paper ] ], [ @kitchen, [ soap ] ] ], costco
    assert_equal [ [ @bathrooms, [ wipes ] ] ], list.second.last
    assert_equal [ [ @kitchen, [ salt ] ] ], list.third.last
  end

  test "the shopping list page has a restock tab" do
    @toilet_paper.mark_restock!

    get grocery_lists_url(list: "restock")

    assert_select "button[role=tab]", text: "Restock (1)"
    assert_select "#restock_panel:not(.hidden) h2", text: "Costco"
    assert_select "#restock_panel h3", text: "Bathrooms"
    assert_select "#shopping_restock_item_#{@toilet_paper.id}", text: /Toilet paper/
    assert_select "#groceries_panel.hidden"
  end

  test "the groceries tab is open by default" do
    get grocery_lists_url
    assert_select "#groceries_panel:not(.hidden)"
    assert_select "#restock_panel.hidden p", text: "Nothing to restock right now."
  end

  test "ticking an item off the restock list marks it stocked, and unticking puts it back" do
    @toilet_paper.mark_restock!

    patch mark_stocked_restock_item_url(@toilet_paper), params: { context: "shopping" }, as: :turbo_stream
    assert @toilet_paper.reload.stocked?
    assert_match(/turbo-stream action="replace" target="shopping_restock_item_#{@toilet_paper.id}"/, response.body)
    assert_match(/line-through/, response.body)

    patch mark_restock_restock_item_url(@toilet_paper), params: { context: "shopping" }, as: :turbo_stream
    assert @toilet_paper.reload.restock?
  end

  test "checking in from the checklist still replaces the checklist card" do
    patch mark_restock_restock_item_url(@toilet_paper), as: :turbo_stream
    assert_match(/turbo-stream action="replace" target="restock_item_#{@toilet_paper.id}"/, response.body)
  end

  private

  def restock(name, category, store:, marked: true)
    item = @household.restock_items.create!(name:, restock_category: category, store:, user: users(:one))
    item.mark_restock! if marked
    item
  end
end
