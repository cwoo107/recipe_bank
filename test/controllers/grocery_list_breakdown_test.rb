require "test_helper"

# The grocery list's "used in N meals" hover: the recipes, how often each is
# planned that week, and the total amount needed.
class GroceryListBreakdownTest < ActionDispatch::IntegrationTest
  setup do
    @user      = users(:one)
    @household = @user.household
    @week      = Date.current.beginning_of_week
    @household.grocery_lists.destroy_all
    @household.meals.destroy_all

    @flour = @household.ingredients.create!(ingredient: "Hover flour", family: "baking")
    pancakes = @user.recipes.create!(title: "Hover pancakes", servings: 4, visibility: "private")
    pancakes.recipe_ingredients.create!(ingredient: @flour, quantity: 2, unit: "cup")
    gravy = @user.recipes.create!(title: "Hover gravy", servings: 4, visibility: "private")
    gravy.recipe_ingredients.create!(ingredient: @flour, quantity: 4, unit: "tbsp")

    [ [ pancakes, 0 ], [ pancakes, 2 ], [ gravy, 3 ] ].each do |recipe, day|
      @household.meals.create!(user: @user, recipe:, meal_name: "Dinner", date: @week + day)
    end
    sign_in @user
  end

  test "the total shows on the row; the hover lists the recipes" do
    post generate_grocery_lists_url, params: { date: @week }
    line = @household.grocery_lists.find_by!(ingredient: @flour)

    get grocery_lists_url(date: @week)

    assert_select "##{ActionView::RecordIdentifier.dom_id(line)}" do
      assert_select "span", text: "4 ¼ cups needed" # always shown, not in the hover
      assert_select "[aria-describedby]", text: /used in 3 meals/
      assert_select "[role=tooltip]", text: /Hover pancakes\s*× 2\s*Hover gravy\s*× 1/
      assert_select "[role=tooltip]", text: /needed/, count: 0
    end
  end

  test "a re-rendered row (ticked off) keeps its hover" do
    post generate_grocery_lists_url, params: { date: @week }
    line = @household.grocery_lists.find_by!(ingredient: @flour)

    patch grocery_list_url(line), params: { grocery_list: { checked: "1", units: line.units } }, as: :turbo_stream

    assert_match "4 ¼ cups needed", response.body
  end

  test "an item added by hand has no total or hover" do
    @household.grocery_lists.create!(user: @user, ingredient: @flour, units: 1, week_of: @week)

    get grocery_lists_url(date: @week)

    assert_select "#grocery_lists", text: /used in 0 meals/
    assert_select "[role=tooltip]", 0
    assert_no_match "needed", response.body
  end

  # Otherwise a browser can put a box back ticked after a reload when the
  # saved row (and so its strikethrough) is unticked.
  test "row forms opt out of the browser restoring their state on reload" do
    post generate_grocery_lists_url, params: { date: @week }
    @household.grocery_lists.create!(user: @user, note: "Candles", week_of: @week)

    get grocery_lists_url(date: @week)

    assert_select "#grocery_lists form[method=post][autocomplete=off] input[type=checkbox]", 2
  end
end
