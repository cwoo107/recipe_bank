require "test_helper"

class RecipePickerFormsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)
    @carol = users(:three)
    @ours   = @alice.recipes.create!(title: "Household Stew",  visibility: "private")
    @theirs = @carol.recipes.create!(title: "Public Paella",   visibility: "public")
    sign_in @alice
  end

  test "meal form renders household recipes and public ones marked for opt-in" do
    get new_meal_url
    assert_response :success
    assert_match "Household Stew", response.body
    assert_match "Public Paella", response.body
    assert_match "Also browse public recipes", response.body
    assert_match "data-public=\"true\"", response.body
  end

  test "recurring meal edit lists only household recipes" do
    recurring = RecurringMeal.create!(household: households(:one), user: @alice, recipe: @ours,
                                      meal_name: "dinner", pattern_type: "days_of_week",
                                      days_of_week: ["monday"], start_date: Date.current)
    get edit_recurring_meal_url(recurring)
    assert_response :success
    assert_match "Household Stew", response.body
    assert_no_match "Public Paella", response.body
  end
end
