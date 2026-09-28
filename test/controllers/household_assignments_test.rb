require "test_helper"

class HouseholdAssignmentsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @household = households(:one) # alice (owner) + bob, family size 3
    @alice = household_members(:alice)
    @bob   = household_members(:one)
    @meal  = meals(:one) # Wed Jan 7 2026
    sign_in users(:one)
  end

  # ── Family size & members ──

  test "family size is editable in household settings" do
    patch household_url, params: { household: { family_size: "5" } }
    assert_equal 5, @household.reload.family_size
  end

  test "adding a member with no email creates no login and bumps the family size when needed" do
    @household.update!(family_size: 2)

    assert_no_emails do
      assert_no_difference("User.count") do
        post household_members_url, params: { household_member: { name: "Kid", email: "" } }
      end
    end

    assert_redirected_to household_url
    assert_equal 3, @household.reload.family_size
  end

  test "the owner can't be removed" do
    delete household_member_url(@alice)

    assert HouseholdMember.exists?(@alice.id)
    assert_equal "The owner can't be removed from their household.", flash[:alert]
  end

  test "removing a member with a login keeps everything they added, handed to the owner" do
    bob_user = users(:two)
    recipe = Recipe.create!(title: "Bob's chili", servings: 4, user: bob_user)
    meal   = @household.meals.create!(recipe:, user: bob_user, meal_name: "Dinner", date: Date.new(2026, 1, 8), eater_ids: [ @bob.id ])
    todo   = @household.todos.create!(title: "Fix fence", priority: :medium, status: "todo", user: bob_user, assignee: @bob)
    rule   = @household.recurring_meals.create!(user: bob_user, recipe:, meal_name: "Lunch", pattern_type: "interval",
                                                interval_days: 1, start_date: Date.new(2026, 1, 5), end_type: "ongoing")

    delete household_member_url(@bob)

    assert_redirected_to household_url
    assert_not HouseholdMember.exists?(@bob.id)
    assert_not User.exists?(bob_user.id)

    assert_equal users(:one), recipe.reload.user
    assert_equal users(:one), meal.reload.user
    assert_empty meal.eater_ids, "his meal assignments go with him"
    assert_equal users(:one), todo.reload.user
    assert_nil todo.assignee
    assert_equal users(:one), rule.reload.user
  end

  test "the members list links each name to their summary and shows the owner first" do
    get household_url
    assert_select "#household_members li:first-child a[href='#{household_member_path(@alice)}']", text: "Alice"
    assert_select "a[href='#{household_member_path(@bob)}']", text: "Bob"
  end

  # ── Meals ──

  test "new meals default to the family size" do
    get new_meal_url
    assert_select "input[name='meal[servings]'][value='3']"

    post meals_url, params: { meal: { recipe_id: recipes(:one).id, meal_name: "Lunch", date: "2026-01-06", servings: "" } }
    assert_equal 3, Meal.last[:servings]
  end

  test "who's eating is optional and only accepts household members" do
    post meals_url, params: { meal: { recipe_id: recipes(:one).id, meal_name: "Breakfast", date: "2026-01-06",
                                      eater_ids: [ "", @bob.id, household_members(:carol).id ] } }

    assert_equal [ @bob.id ], Meal.last.eater_ids
  end

  test "editing a meal can clear who's eating" do
    @meal.update!(eater_ids: [ @bob.id ])

    patch meal_url(@meal), params: { meal: { servings: 4, eater_ids: [ "" ] } }

    assert_empty @meal.reload.eater_ids
  end

  test "the meal form shows the who's eating picker" do
    get new_meal_url
    assert_select "details summary", text: /Who's eating/
    assert_select "input[type=checkbox][name='meal[eater_ids][]']", count: 2
  end

  test "households with only the owner never see assignment controls" do
    sign_in User.create!(email: "solo@example.com", password: "password123")

    get new_meal_url
    assert_select "input[name='meal[eater_ids][]']", count: 0

    get new_todo_url
    assert_select "select[name='todo[assignee_id]']", count: 0
  end

  test "week summary only offers the person switcher once someone is assigned a meal" do
    get meals_url(date: "2026-01-05")
    assert_select "#week_stats_body a", text: "Everyone", count: 0

    @meal.update!(eater_ids: [ @bob.id ])
    get meals_url(date: "2026-01-05")
    assert_select "#week_stats_body a[href*='member_id=#{@bob.id}']", text: "Bob"
  end

  test "the week summary for one person lists their meals" do
    @meal.update!(eater_ids: [ @bob.id ])

    get week_stats_meals_url(date: "2026-01-05", member_id: @bob.id)
    assert_select "turbo-frame#week_stats_body"
    assert_select "p", text: "Bob's meals"

    get week_stats_meals_url(date: "2026-01-05", member_id: @alice.id)
    assert_select "p", text: "No meals for Alice this week."
  end

  # ── To-dos & chores ──

  test "a to-do can be assigned to a household member, but not someone else's" do
    post todos_url, params: { todo: { title: "Fix fence", priority: "medium", status: "todo", assignee_id: @bob.id } }
    assert_equal @bob, Todo.last.assignee

    post todos_url, params: { todo: { title: "Paint", priority: "medium", status: "todo", assignee_id: household_members(:carol).id } }
    assert_nil Todo.last.assignee
  end

  test "reassigning a chore carries over to this week's unfinished instances" do
    travel_to Date.new(2026, 1, 7)
    chore = chores(:one) # assigned to bob
    open_one = @household.weekly_chores.create!(chore:, week_start: Date.new(2026, 1, 5), scheduled_date: Date.new(2026, 1, 8))

    chore.update!(assignee: @alice)

    assert_equal @alice, open_one.reload.assignee
  end

  # ── Member summary ──

  test "any household member can open a member's summary" do
    travel_to Date.new(2026, 1, 7)
    @meal.update!(eater_ids: [ @bob.id ])
    @household.todos.create!(title: "Fix fence", priority: :medium, status: "done", user: users(:one), assignee: @bob,
                             start_date: Date.new(2026, 1, 5), end_date: Date.new(2026, 1, 6))
    @household.weekly_chores.create!(chore: chores(:one), week_start: Date.new(2026, 1, 5), scheduled_date: Date.new(2026, 1, 6),
                                     assignee: @bob, completed: true)

    sign_in users(:two) # bob, limited
    get household_member_url(@bob)

    assert_response :success
    assert_select "h1", text: "Bob"
    assert_select "td a", text: recipes(:one).title
    assert_select "td", text: "All"
    assert_select "li", text: /Fix fence/
    assert_select "span", text: "1 of 1 done"
  end

  test "a member's summary can step back through weeks" do
    get household_member_url(@bob, date: "2026-01-07")
    assert_select "p", text: /Week of Jan 5/
  end
end
