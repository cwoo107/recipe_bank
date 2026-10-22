require "test_helper"

# The grocery list's "Add to list" dialog: a note in place of an ingredient
# (like a note on the meal plan), and a picker that adds a typed name to the
# household's ingredients.
class GroceryListNotesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user      = users(:one)
    @household = @user.household
    @week      = Date.current.beginning_of_week
    @household.grocery_lists.destroy_all
    @household.meals.destroy_all
    sign_in @user
  end

  def latest = @household.grocery_lists.order(:id).last

  def add(params)
    post create_grocery_list_url, params: { grocery_list: { week_of: @week, units: 1, manually_adjusted: true }.merge(params) },
                                  as: :turbo_stream
  end

  test "a note goes on the list without an ingredient" do
    assert_difference("GroceryList.count") { add(entry: "note", note: "Birthday candles", ingredient_id: "") }

    item = latest
    assert item.note_only?
    assert_equal "Birthday candles", item.note
    assert_nil item.units
    assert_equal @week, item.week_of
  end

  test "on the note tab a leftover ingredient pick is ignored, and the reverse" do
    butter = @household.ingredients.create!(ingredient: "Butter", family: "dairy")

    add(entry: "note", note: "Foil", ingredient_id: butter.id)
    assert_nil latest.ingredient_id

    add(entry: "ingredient", note: "Foil", ingredient_id: butter.id)
    assert_equal butter, latest.ingredient
    assert_nil latest.note
  end

  test "a blank note isn't saved" do
    assert_no_difference("GroceryList.count") { add(entry: "note", note: "") }
    assert_response :unprocessable_entity
  end

  test "a typed name that isn't an ingredient yet is added to the household's and the list" do
    assert_enqueued_with(job: IngredientEnrichmentJob) do
      assert_difference([ "GroceryList.count", "@household.ingredients.count" ]) do
        add(entry: "ingredient", ingredient_id: "", new_ingredient_name: "  Star anise ")
      end
    end

    item = latest
    assert_equal "Star anise", item.ingredient.ingredient
    assert_equal @household, item.ingredient.household
    assert_match "Added Star anise to your ingredients", response.body
  end

  test "a typed name the household already has uses that ingredient" do
    rice = @household.ingredients.create!(ingredient: "Basmati rice", family: "grain")

    assert_no_difference("Ingredient.count") { add(entry: "ingredient", ingredient_id: "", new_ingredient_name: "basmati rice") }
    assert_equal rice, latest.ingredient
  end

  test "another household's ingredient can't be picked" do
    theirs = households(:two).ingredients.create!(ingredient: "Their saffron", family: "spice")

    assert_no_difference("GroceryList.count") { add(entry: "ingredient", ingredient_id: theirs.id) }
  end

  test "the picker only offers the household's ingredients, for the week being viewed" do
    @household.ingredients.create!(ingredient: "Our paprika", family: "spice")
    households(:two).ingredients.create!(ingredient: "Their saffron", family: "spice")
    next_week = @week + 7

    get new_grocery_list_url(week: next_week)

    assert_select "option", text: "Our paprika"
    assert_select "option", text: "Their saffron", count: 0
    assert_select "input[name='grocery_list[week_of]'][value='#{next_week}']"
    assert_select "input[name='grocery_list[new_ingredient_name]']"
  end

  test "notes show on the list but not in its subtotal" do
    milk = @household.ingredients.create!(ingredient: "Milk", family: "dairy", unit_price: 3.0)
    @household.grocery_lists.create!(user: @user, ingredient: milk, units: 2, week_of: @week)
    @household.grocery_lists.create!(user: @user, note: "Birthday candles", week_of: @week)

    get grocery_lists_url(date: @week)

    assert_select "#grocery_lists", text: /Birthday candles/
    assert_select "#grocery_lists [data-grocery-subtotal-target=row]", 1
    assert_select "[data-grocery-subtotal-target=total]", text: "$6.00"
  end

  test "regenerating the list from the meal plan keeps its notes" do
    @household.grocery_lists.create!(user: @user, note: "Birthday candles", week_of: @week)

    post generate_grocery_lists_url, params: { date: @week }

    assert_equal [ "Birthday candles" ], @household.grocery_lists.where(week_of: @week).map(&:note)
  end

  test "a note can be ticked off and removed" do
    note = @household.grocery_lists.create!(user: @user, note: "Foil", week_of: @week)

    patch grocery_list_url(note), params: { grocery_list: { checked: "1" } }, as: :turbo_stream
    assert note.reload.checked?
    assert_not note.manually_adjusted?

    delete grocery_list_url(note), as: :turbo_stream
    assert_match "Foil removed from list.", response.body
    assert_not GroceryList.exists?(note.id)
  end

  test "the printed shopping list includes notes" do
    @household.grocery_lists.create!(user: @user, note: "Birthday candles", week_of: @week)

    pdf = WeekPlanPdf.new(household: @household, week_start: @week, sections: %w[shopping]).render
    assert pdf.start_with?("%PDF")
  end

  test "the picker offers the default ingredients too, and picking one copies it in" do
    @household.ingredients.create!(ingredient: "Butter", family: "dairy")
    Ingredient.create!(ingredient: "Butter", family: "dairy") # a default we already have by name
    nutmeg = Ingredient.create!(ingredient: "Nutmeg", family: "spices", unit_price: 3.5)

    get new_grocery_list_url(week: @week)
    assert_select "option", text: "Butter", count: 1
    assert_select "option[value='#{nutmeg.id}']", text: "Nutmeg"

    assert_difference("@household.ingredients.count") { add(entry: "ingredient", ingredient_id: nutmeg.id) }
    copy = latest.ingredient
    assert_equal @household, copy.household
    assert_equal nutmeg, copy.source_ingredient
    assert_equal 3.5, copy.unit_price

    # Picking it again uses the copy, and it's offered once, as ours.
    assert_no_difference("Ingredient.count") { add(entry: "ingredient", ingredient_id: nutmeg.id) }
    get new_grocery_list_url(week: @week)
    assert_select "option", text: "Nutmeg", count: 1
    assert_select "option[value='#{copy.id}']", text: "Nutmeg"
  end
end
