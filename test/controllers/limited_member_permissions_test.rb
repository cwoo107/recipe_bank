require "test_helper"

# What a limited household member (Bob) can and can't do. Admins and owners
# can do everything; see ApplicationController.
class LimitedMemberPermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @alice = users(:one)             # owner
    @bob   = users(:two)             # limited member
    @bob_member = household_members(:one)
    @meal = meals(:one)
    sign_in @bob
  end

  # ── Recipes, meals, lists: look, don't touch ──

  test "recipes are read-only" do
    recipe = @alice.recipes.create!(title: "Chili", servings: 4, visibility: "private")

    get recipe_url(recipe)
    assert_response :success
    assert_select "button[data-action='click->edit-mode#toggle']", count: 0

    get new_recipe_url
    assert_redirected_to root_url

    assert_no_difference("Recipe.count") { post recipes_url, params: { recipe: { title: "Nope" } } }
    assert_no_difference("Recipe.count") { post duplicate_recipe_url(recipe) }
  end

  test "meals are read-only" do
    get meals_url(date: @meal.date.beginning_of_week)
    assert_response :success
    assert_select "button", text: /Add a meal/, count: 0
    assert_select "#meal_#{@meal.id} button", text: "Edit", count: 0
    assert_select "button[aria-label^='Add dinner']", count: 0

    assert_no_difference("Meal.count") do
      post meals_url, params: { meal: { recipe_id: recipes(:one).id, meal_name: "Lunch", date: @meal.date } }
    end
    patch meal_url(@meal), params: { meal: { servings: 9 } }
    assert_not_equal 9, @meal.reload[:servings]
    assert_no_difference("Meal.count") { delete meal_url(@meal) }
  end

  test "grocery lists are view-only, even ticking items off" do
    item = @household.grocery_lists.create!(ingredient: ingredients(:one), user: @alice, week_of: Date.current.beginning_of_week, units: 1)

    get grocery_lists_url
    assert_response :success
    assert_select "body[data-limited]"
    assert_select "button", text: /Auto generate list/, count: 0
    assert_select "#grocery_list_#{item.id} .admin-only input[type=checkbox]" # hidden by CSS for limited members

    patch grocery_list_url(item), params: { grocery_list: { checked: "1" } }
    assert_not item.reload.checked?
    assert_no_difference("GroceryList.count") { post generate_grocery_lists_url }
  end

  test "the restock checklist and restock list are view-only" do
    toilet_paper = restock_items(:one)
    toilet_paper.mark_restock!

    get restock_items_url
    assert_response :success
    assert_select "button", text: /Add an item/, count: 0
    assert_select "#restock_item_#{toilet_paper.id} form", count: 0

    get grocery_lists_url(list: "restock")
    assert_select "#shopping_restock_item_#{toilet_paper.id} form", count: 0

    patch mark_stocked_restock_item_url(toilet_paper), params: { context: "shopping" }
    assert toilet_paper.reload.restock?
  end

  test "calendar entries can't be changed" do
    get month_calendars_url(year: Date.current.year, month: Date.current.month)
    assert_response :success
    assert_select "a[href='#{new_calendar_event_path}']", count: 0

    get new_calendar_event_url
    assert_redirected_to root_url
  end

  # ── To-dos ──

  test "a to-do they add is assigned to them, and they can edit it" do
    post todos_url, params: { todo: { title: "Clean my room", priority: "medium", status: "todo",
                                      assignee_id: household_members(:alice).id } }
    todo = Todo.last
    assert_equal @bob_member, todo.assignee, "always themselves, whatever was sent"

    patch todo_url(todo), params: { todo: { title: "Clean my room well" } }
    assert_equal "Clean my room well", todo.reload.title
  end

  test "someone else's to-do can't be edited, moved or deleted" do
    todo = todos(:one) # alice's, unassigned

    get todos_url
    assert_select "#todo_#{todo.id} .sortable-handle", count: 0
    assert_select "#todo_#{todo.id} dialog", count: 0

    patch todo_url(todo), params: { todo: { title: "Hijacked" } }
    assert_equal "Take out the trash", todo.reload.title

    post move_todo_url(todo), params: { status: "done" }, as: :json
    assert_response :forbidden
    assert_equal "todo", todo.reload.status

    assert_no_difference("Todo.count") { delete todo_url(todo) }
  end

  test "a to-do assigned to them can be moved to done, but not edited" do
    todo = todos(:one)
    todo.update!(assignee: @bob_member)

    get todos_url
    assert_select "#todo_#{todo.id} .sortable-handle"
    assert_select "#todo_#{todo.id} dialog", count: 0

    post move_todo_url(todo), params: { status: "done" }, as: :turbo_stream
    assert_equal "done", todo.reload.status

    patch todo_url(todo), params: { todo: { title: "Hijacked" } }
    assert_equal "Take out the trash", todo.reload.title
  end

  test "reordering a column is admin-only" do
    post reorder_todos_url, params: { status: "todo", order: [ todos(:one).id ] }, as: :json
    assert_response :forbidden
  end

  # ── Chores ──

  test "they can tick off their own chores, and only that" do
    week = Date.current.beginning_of_week
    mine   = @household.weekly_chores.create!(chore: chores(:one), week_start: week, scheduled_date: week, assignee: @bob_member)
    theirs = @household.weekly_chores.create!(chore: @household.chores.create!(name: "Dishes", frequency: "weekly"),
                                              week_start: week, scheduled_date: week, assignee: household_members(:alice))

    get weekly_chores_url
    assert_select "#weekly_chore_#{mine.id} input[type=checkbox]:not([disabled])"
    assert_select "#weekly_chore_#{theirs.id} input[type=checkbox][disabled]"
    assert_select "[data-controller=chore-board]", count: 0

    patch weekly_chore_url(mine), params: { weekly_chore: { completed: "1" } }, as: :turbo_stream
    assert mine.reload.completed?

    patch weekly_chore_url(theirs), params: { weekly_chore: { completed: "1" } }, as: :turbo_stream
    assert_not theirs.reload.completed?

    patch weekly_chore_url(mine), params: { weekly_chore: { assignee_id: household_members(:alice).id } }, as: :turbo_stream
    assert_equal @bob_member, mine.reload.assignee, "can't hand it off"

    post move_weekly_chore_url(mine), params: { scheduled_date: (week + 2).iso8601 }, as: :json
    assert_response :forbidden
  end

  test "chores can't be created or edited" do
    get new_chore_url
    assert_redirected_to root_url
    assert_no_difference("Chore.count") { post chores_url, params: { chore: { name: "Nope", frequency: "weekly" } } }
  end

  # ── Plan your week ──

  test "limited members can't plan the week or see the planning popup" do
    WeeklyPlan.current_for(@household).update!(currently_planning: true)

    get plan_week_url
    assert_redirected_to root_url

    get todos_url
    assert_select "form[action^='/plan-week']", count: 0

    get dashboard_url
    assert_select "a", text: /Plan your week|Continue planning|Plan next week/, count: 0
    assert_select "a[href='#{meals_path(date: Date.current.beginning_of_week)}']", text: "View meals"
  end

  test "other admins do see the planning popup" do
    WeeklyPlan.current_for(@household).update!(currently_planning: true)
    @bob_member.update!(role: :admin)

    get todos_url
    assert_select "form[action^='/plan-week']"
  end

  test "every page still renders for a limited member" do
    [ dashboard_url, recipes_url, meals_url, grocery_lists_url, grocery_lists_url(list: "restock"), restock_items_url,
      chores_url, weekly_chores_url, todos_url, month_calendars_url(year: 2026, month: 1),
      week_calendars_url, day_calendars_url, household_url, household_member_url(@bob_member) ].each do |url|
      get url
      assert_response :success, "expected #{url} to render"
    end
  end

  test "and for an admin, with every control in place" do
    sign_in @alice
    [ dashboard_url, recipes_url, meals_url, grocery_lists_url(list: "restock"), restock_items_url,
      chores_url, weekly_chores_url, todos_url, month_calendars_url(year: 2026, month: 1),
      week_calendars_url, day_calendars_url ].each do |url|
      get url
      assert_response :success, "expected #{url} to render"
      assert_select "body[data-limited]", count: 0
    end

    get meals_url
    assert_select "button", text: /Add a meal/
  end
end
