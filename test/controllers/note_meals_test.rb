require "test_helper"

# A note in place of a recipe — eating out, at a friend's — that holds the
# slot without anything to cook.
class NoteMealsTest < ActionDispatch::IntegrationTest
  setup do
    @recipe = recipes(:one)
    @date   = Date.new(2026, 1, 7)
    sign_in users(:one) # alice, household one
  end

  test "creating a note meal ignores any recipe left in the picker" do
    assert_difference("Meal.count") do
      post meals_url, params: { meal: { entry: "note", note: "Dinner at the Smiths'", recipe_id: @recipe.id,
                                        meal_name: "Dinner", date: @date } }
    end

    meal = Meal.order(:id).last
    assert meal.note_only?
    assert_nil meal.recipe
    assert_equal "Dinner at the Smiths'", meal.title
  end

  test "a note meal needs a note" do
    assert_no_difference("Meal.count") do
      post meals_url, params: { meal: { entry: "note", note: "", meal_name: "Dinner", date: @date } }
    end
    assert_response :unprocessable_entity
  end

  test "a note can't be made recurring" do
    assert_no_difference("RecurringMeal.count") do
      post meals_url, params: { meal: { entry: "note", note: "Pizza night out", meal_name: "Dinner", date: @date,
                                        recurring: { enabled: "1", pattern_type: "interval", interval_days: 7,
                                                     start_date: @date, end_type: "never" } } }
    end
    assert Meal.order(:id).last.note_only?
  end

  test "switching an existing meal between recipe and note clears the other" do
    meal = meals(:one)

    patch meal_url(meal), params: { meal: { entry: "note", note: "Takeout", recipe_id: meal.recipe_id } }
    assert meal.reload.note_only?
    assert_equal "Takeout", meal.note

    patch meal_url(meal), params: { meal: { entry: "recipe", note: "Takeout", recipe_id: @recipe.id } }
    assert_equal @recipe, meal.reload.recipe
    assert_nil meal.note
  end

  test "the week shows note meals with their own look and no recipe link" do
    note = households(:one).meals.create!(user: users(:one), note: "Eating out", meal_name: "Lunch", date: @date)

    get meals_url(date: @date)

    assert_response :success
    assert_select "#meal_#{note.id}.bg-taupe-200", text: /Eating out.*Not cooking/m
    assert_select "#meal_#{note.id} a[href^='/recipes/']", count: 0
  end

  test "the edit form opens on the note side for note meals" do
    note = households(:one).meals.create!(user: users(:one), note: "Eating out", meal_name: "Lunch", date: @date)

    get edit_meal_url(note)
    assert_select "input[type=hidden][name='meal[entry]'][value='note']"
    assert_select "button[data-source='note'][aria-current='page']", text: /Make a Note/
    assert_select "[data-meal-form-target='recipeSection'].hidden"
    assert_select "[data-meal-form-target='noteSection']:not(.hidden)"
  end

  test "a new meal opens on the recipe search tab" do
    get new_meal_url
    assert_select "input[type=hidden][name='meal[entry]'][value='recipe']"
    assert_select "button[data-searchable-select-target='searchTab'][aria-current='page']"
    assert_select "[data-meal-form-target='noteSection'].hidden"
  end

  test "grocery lists and the week plan PDF skip note meals" do
    households(:one).meals.create!(user: users(:one), note: "Eating out", meal_name: "Lunch", date: @date)

    post generate_grocery_lists_url, params: { date: @date.beginning_of_week }
    assert_response :redirect

    get week_print_url(format: :pdf, week: @date.iso8601, sections: WeekPlanPdf::SECTIONS.keys)
    assert_response :success
  end
end
