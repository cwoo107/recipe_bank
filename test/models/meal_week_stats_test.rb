require "test_helper"

class MealWeekStatsTest < ActiveSupport::TestCase
  FakeRecipe = Struct.new(:title)
  FakeMeal = Struct.new(:shares, :scaled_calories, :scaled_protein, :scaled_carbs, :scaled_fat, :total_cost, keyword_init: true) do
    def share_for(member, excluded_ids: []) = shares.fetch(member)
    def slot = nil
    def eater_ids_assigned = []
    def recipe = FakeRecipe.new("Eggs")
    def meal_name = "Breakfast"
    def date = Date.new(2026, 1, 5)
  end

  test "a member's totals are their share of each meal" do
    dad = :dad
    eggs    = FakeMeal.new(shares: { dad => 1.0, nil => 1.0 }, scaled_calories: 700, scaled_protein: 42, scaled_carbs: 2, scaled_fat: 50, total_cost: 3.5)
    oatmeal = FakeMeal.new(shares: { dad => 0.0, nil => 1.0 }, scaled_calories: 900, scaled_protein: 30, scaled_carbs: 150, scaled_fat: 15, total_cost: 2.0)
    dinner  = FakeMeal.new(shares: { dad => 0.25, nil => 1.0 }, scaled_calories: 2000, scaled_protein: 120, scaled_carbs: 200, scaled_fat: 80, total_cost: 20.0)

    stats = MealWeekStats.new([ eggs, oatmeal, dinner ], member: dad).to_h

    assert_equal 2, stats[:meal_count], "the oatmeal isn't his"
    assert_equal 1200, stats[:total_calories]
    assert_equal 72.0, stats[:total_protein]
    assert_equal 8.5, stats[:total_cost]
    assert_equal (1200 / 7.0).round, stats[:per_serv_calories]

    household = MealWeekStats.new([ eggs, oatmeal, dinner ]).to_h
    assert_equal 3600, household[:total_calories]
  end

  test "someone with their own meal in a slot is left out of that slot's shared meal" do
    household = households(:one) # family size 3: alice, bob, one more
    alice, bob = household_members(:alice), household_members(:one)
    monday = Date.new(2026, 1, 5)
    burritos = household.meals.create!(recipe: recipes(:one), user: users(:one), meal_name: "Breakfast", date: monday, eater_ids: [ bob.id ])
    pancakes = household.meals.create!(recipe: recipes(:two), user: users(:one), meal_name: "Breakfast", date: monday)
    dinner   = household.meals.create!(recipe: recipes(:two), user: users(:one), meal_name: "Dinner", date: monday)
    meals = household.meals.where(id: [ burritos, pancakes, dinner ]).includes(:meal_assignments, :household)

    shares = ->(member) { MealWeekStats.new(meals, member:).rows.to_h { |r| [ r[:meal].id, r[:share] ] } }

    assert_equal({ burritos.id => 1.0, dinner.id => 1.0 / 3 }, shares.(bob), "no pancakes for bob, still shares dinner")
    assert_equal({ pancakes.id => 0.5, dinner.id => 1.0 / 3 }, shares.(alice), "the other two split the pancakes")
  end

  test "rows are in eating order: by day, then breakfast, lunch, dinner" do
    household = households(:one)
    monday, tuesday = Date.new(2026, 1, 5), Date.new(2026, 1, 6)
    make = ->(name, date) { household.meals.create!(recipe: recipes(:one), user: users(:one), meal_name: name, date: date) }
    tue_breakfast = make.("Breakfast", tuesday)
    mon_dinner    = make.("Dinner", monday)
    mon_breakfast = make.("Breakfast", monday)
    mon_lunch     = make.("Lunch", monday)

    rows = MealWeekStats.new(household.meals.where(date: monday..tuesday), member: household_members(:alice)).rows

    assert_equal [ mon_breakfast, mon_lunch, mon_dinner, tue_breakfast ], rows.map { |r| r[:meal] }
  end
end
