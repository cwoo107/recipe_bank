require "test_helper"

class MealServingsTest < ActionDispatch::IntegrationTest
  MONDAY = Date.new(2026, 1, 5)

  setup do
    @household = households(:one) # family size 3: alice, bob, one unlisted
    @bob = household_members(:one)
    sign_in users(:one)
  end

  test "a new meal's servings start blank, for the picked recipe to fill in" do
    add_meal("Breakfast", eaters: [ @bob ])
    chicken = users(:one).recipes.create!(title: "Marry Me Chicken", servings: 4)

    get new_meal_url(date: MONDAY.iso8601, meal_name: "Breakfast")

    assert_select "input[name='meal[servings]']:not([value])"
    # What each recipe makes, for meal-form#recipeChanged to fill in.
    assert_select "option[value='#{chicken.id}'][data-servings='4']"
  end

  test "creating without servings uses what the recipe makes, whoever's eating" do
    add_meal("Breakfast", eaters: [ @bob ])

    post meals_url, params: { meal: { recipe_id: recipes(:two).id, meal_name: "Breakfast", date: MONDAY.iso8601, servings: "" } }
    assert_equal recipes(:two).servings, Meal.last[:servings]

    post meals_url, params: { meal: { recipe_id: recipes(:two).id, meal_name: "Dinner", date: MONDAY.iso8601, servings: "",
                                      eater_ids: [ @bob.id ] } }
    assert_equal recipes(:two).servings, Meal.last[:servings]
  end

  test "a note without servings still counts the people eating it" do
    post meals_url, params: { meal: { entry: "note", note: "Dinner out", meal_name: "Dinner", date: MONDAY.iso8601, servings: "",
                                      eater_ids: [ @bob.id ] } }
    assert_equal 1, Meal.last[:servings]
  end

  test "the meal form knows each slot's assigned people and shared meals" do
    add_meal("Breakfast", eaters: [ @bob ])
    pancakes = add_meal("Breakfast", servings: 2)

    get new_meal_url(date: MONDAY.iso8601)
    data = JSON.parse(css_select("form[data-controller='meal-form']").first["data-meal-form-slot-data-value"])
    assert_equal({ "assigned" => [ @bob.id ],
                   "shared" => [ { "id" => pancakes.id, "title" => recipes(:one).title, "servings" => 2 } ] }, data["2026-01-05|breakfast"])
    assert_select "[data-meal-form-target=sharedPrompt]"
  end

  test "saying yes in the form drops the shared meal's servings when the meal is added" do
    pancakes = add_meal("Breakfast", servings: 3)

    post meals_url, params: { meal: { recipe_id: recipes(:two).id, meal_name: "Breakfast", date: MONDAY.iso8601,
                                      eater_ids: [ @bob.id ], drop_shared_meal_ids: [ pancakes.id ] } }, as: :turbo_stream

    assert_equal 2, pancakes.reload[:servings]
    assert_match(/turbo-stream action="replace" targets="#meal_#{pancakes.id}"/, response.body)
  end

  test "leaving it unticked keeps the shared meal's servings" do
    pancakes = add_meal("Breakfast", servings: 3)

    post meals_url, params: { meal: { recipe_id: recipes(:two).id, meal_name: "Breakfast", date: MONDAY.iso8601,
                                      eater_ids: [ @bob.id ] } }, as: :turbo_stream

    assert_equal 3, pancakes.reload[:servings]
  end

  test "the server re-checks what was ticked — no drop if they were already out of that slot" do
    pancakes = add_meal("Breakfast", servings: 2)
    add_meal("Breakfast", eaters: [ @bob ])

    post meals_url, params: { meal: { recipe_id: recipes(:two).id, meal_name: "Breakfast", date: MONDAY.iso8601,
                                      eater_ids: [ @bob.id ], drop_shared_meal_ids: [ pancakes.id, meals(:two).id ] } }

    assert_equal 2, pancakes.reload[:servings]
    assert_equal 4, meals(:two).reload[:servings], "another household's meal is never touched"
  end

  test "editing a meal to assign someone applies the drop that was ticked" do
    pancakes = add_meal("Breakfast", servings: 3)
    burritos = add_meal("Breakfast", servings: 1)

    patch meal_url(burritos), params: { meal: { servings: 1, eater_ids: [ @bob.id ], drop_shared_meal_ids: [ pancakes.id ] } },
          headers: { "Turbo-Frame" => "edit_meal_#{burritos.id}", "Accept" => "text/vnd.turbo-stream.html, text/html" }

    assert_select "turbo-stream[action=refresh]"
    assert_equal 2, pancakes.reload[:servings]
  end

  test "a recurring meal can take them out of this week's shared meals of that type" do
    travel_to MONDAY
    pancakes = add_meal("Breakfast", servings: 3)
    tuesday_pancakes = @household.meals.create!(recipe: recipes(:one), user: users(:one), meal_name: "Breakfast",
                                                date: MONDAY + 1, servings: 3)

    post meals_url, params: { meal: { recipe_id: recipes(:two).id, meal_name: "Breakfast", eater_ids: [ @bob.id ], drop_shared: "1",
                                      recurring: { enabled: "1", pattern_type: "interval", interval_days: 1,
                                                   start_date: MONDAY.iso8601, end_type: "week" } } }, as: :turbo_stream

    assert_equal 2, pancakes.reload[:servings]
    assert_equal 2, tuesday_pancakes.reload[:servings]
  end

  test "servings never drop below 1" do
    toast = add_meal("Breakfast", servings: 1)

    post meals_url, params: { meal: { recipe_id: recipes(:two).id, meal_name: "Breakfast", date: MONDAY.iso8601,
                                      eater_ids: [ @bob.id ], drop_shared_meal_ids: [ toast.id ] } }

    assert_equal 1, toast.reload[:servings]
  end

  test "a meal with no saved servings counts as what the recipe makes" do
    pancakes = add_meal("Breakfast")
    pancakes.update_column(:servings, nil)

    get edit_meal_url(pancakes)
    assert_select "input[name='meal[servings]']:not([value])"
    assert_equal recipes(:one).servings, pancakes.reload.servings
  end

  private

  def add_meal(name, servings: nil, eaters: [])
    @household.meals.create!(recipe: recipes(:one), user: users(:one), meal_name: name, date: MONDAY,
                             servings: servings || (eaters.any? ? eaters.size : 3), eater_ids: eaters.map(&:id))
  end
end
