require "test_helper"

# Groceries that are also on the restock list: confirmed once after the list
# is generated, then shown on both lists and ticked off together.
class RestockMatchesTest < ActionDispatch::IntegrationTest
  setup do
    @user      = users(:one)
    @household = @user.household
    @week      = Date.current.beginning_of_week
    @household.meals.destroy_all
    @household.grocery_lists.destroy_all

    @oil      = @household.ingredients.create!(ingredient: "Extra virgin olive oil", family: "pantry")
    @oil_line = @household.grocery_lists.create!(ingredient: @oil, week_of: @week, user: @user, units: 1, checked: false)
    @restock_oil = @household.restock_items.create!(name: "Olive oil", restock_category: restock_categories(:kitchen_one),
                                                    user: @user, restock: true)
    sign_in @user
  end

  def link!(linked: true)
    RestockItemIngredient.create!(restock_item: @restock_oil, ingredient: @oil, linked:)
  end

  test "names match on whole words, give or take plurals" do
    assert RestockMatch.same_thing?("Extra virgin olive oil", "Olive oil")
    assert RestockMatch.same_thing?("Large eggs", "Egg")
    assert_not RestockMatch.same_thing?("Salted butter", "Salt")
    assert_not RestockMatch.same_thing?("Foil", "Oil")
  end

  test "generating the list asks about likely restock matches first" do
    recipe = @user.recipes.create!(title: "Salad", visibility: "private", servings: 1)
    recipe.recipe_ingredients.create!(ingredient: @oil, quantity: 1, unit: "tbsp")
    Meal.create!(recipe:, user: @user, household: @household, meal_name: "Dinner", date: @week)

    post generate_grocery_lists_url, params: { date: @week }
    assert_redirected_to new_restock_match_url(date: @week)

    follow_redirect!
    assert_select "input[name='confirmed[]'][value='#{@restock_oil.id}-#{@oil.id}']"
  end

  test "goes straight to the list once a pair has been answered" do
    link!(linked: false)

    get new_restock_match_url(date: @week)
    assert_redirected_to grocery_lists_url(date: @week)
  end

  test "saves ticked pairs as linked and unticked ones as not, so neither is asked again" do
    paper = @household.ingredients.create!(ingredient: "Paper towels", family: "grocery")
    @household.grocery_lists.create!(ingredient: paper, week_of: @week, user: @user, units: 1)
    towels = @household.restock_items.create!(name: "Paper towel", restock_category: restock_categories(:kitchen_one),
                                              user: @user, restock: true)

    post restock_matches_url(date: @week), params: { confirmed: [ "#{@restock_oil.id}-#{@oil.id}" ] }

    assert_redirected_to grocery_lists_url(date: @week)
    assert RestockItemIngredient.find_by!(restock_item: @restock_oil, ingredient: @oil).linked?
    assert_not RestockItemIngredient.find_by!(restock_item: towels, ingredient: paper).linked?
    assert_empty RestockMatch.suggestions(@household, @week)
  end

  test "can't link another household's restock item" do
    other = restock_items(:two)
    other.update!(name: "Olive oil", restock: true)

    post restock_matches_url(date: @week), params: { confirmed: [ "#{other.id}-#{@oil.id}" ] }

    assert_not RestockItemIngredient.exists?(restock_item: other)
  end

  test "linked lines say they're on the other list" do
    link!

    get grocery_lists_url(date: @week)

    assert_select "#grocery_list_#{@oil_line.id}", text: /also on restock list/
    assert_select ".shopping_restock_item_#{@restock_oil.id}", text: /also on grocery list/
  end

  test "a rejected pair isn't labelled" do
    link!(linked: false)

    get grocery_lists_url(date: @week)

    assert_select "#grocery_list_#{@oil_line.id}", text: /also on restock list/, count: 0
  end

  test "ticking the grocery line ticks off the restock item, and unticking puts it back" do
    link!

    patch grocery_list_url(@oil_line, format: :turbo_stream), params: { grocery_list: { checked: "1" } }
    assert @restock_oil.reload.bought_today?
    assert_match(/targets=".shopping_restock_item_#{@restock_oil.id}"/, response.body)

    patch grocery_list_url(@oil_line, format: :turbo_stream), params: { grocery_list: { checked: "0" } }
    assert @restock_oil.reload.restock?
  end

  test "ticking the restock item ticks the grocery line, and unticking unticks it" do
    link!

    patch mark_stocked_restock_item_url(@restock_oil), params: { context: "shopping", date: @week.to_s }, as: :turbo_stream
    assert @oil_line.reload.checked?
    assert_match(/target="grocery_list_#{@oil_line.id}"/, response.body)

    patch mark_restock_restock_item_url(@restock_oil), params: { context: "shopping", date: @week.to_s }, as: :turbo_stream
    assert_not @oil_line.reload.checked?
  end

  test "generating the list leaves off ingredients whose restock item is stocked" do
    link!
    @restock_oil.mark_stocked!
    recipe = @user.recipes.create!(title: "Salad", visibility: "private", servings: 1)
    recipe.recipe_ingredients.create!(ingredient: @oil, quantity: 1, unit: "tbsp")
    Meal.create!(recipe:, user: @user, household: @household, meal_name: "Dinner", date: @week)

    post generate_grocery_lists_url, params: { date: @week }

    assert_not @household.grocery_lists.exists?(ingredient: @oil)
    assert_match "Left off Extra virgin olive oil", flash[:notice]
  end

  test "the restock checklist links to the linked-ingredients page" do
    get restock_items_url
    assert_select "a[href='#{restock_matches_path}']", text: "Manage linked ingredients"
  end

  test "linked and not-the-same pairs are listed and can be switched" do
    pair = link!
    get restock_matches_url
    assert_select "##{ActionView::RecordIdentifier.dom_id(pair)}", text: /Unlink/

    patch restock_match_url(pair), params: { linked: false }
    assert_redirected_to restock_matches_url
    assert_not pair.reload.linked?

    patch restock_match_url(pair), params: { linked: true }
    assert pair.reload.linked?
  end

  test "can't change another household's pair" do
    other = RestockItemIngredient.create!(restock_item: restock_items(:two), ingredient: @oil)

    patch restock_match_url(other), params: { linked: false }
    assert_response :not_found
    assert other.reload.linked?
  end

  test "Select all ticks off linked restock items" do
    link!

    patch check_all_grocery_lists_url, params: { date: @week }
    assert @restock_oil.reload.bought_today?
  end
end
