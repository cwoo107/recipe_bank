require "test_helper"

class TodosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @todo = todos(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get todos_url
    assert_response :success
  end

  test "should create todo" do
    assert_difference("Todo.count") do
      post todos_url, params: { todo: { title: "New task", priority: "medium", status: "todo" } }
    end

    assert_equal households(:one), Todo.last.household
  end

  test "should update todo" do
    patch todo_url(@todo), params: { todo: { title: "Updated" } }
    assert_redirected_to todos_url
    assert_equal "Updated", @todo.reload.title
  end

  test "should destroy todo" do
    assert_difference("Todo.count", -1) do
      delete todo_url(@todo)
    end
  end

  test "an admin in the same household can edit someone else's todo" do
    household_members(:one).update!(role: :admin)
    sign_in users(:two) # bob, now an admin in household :one

    patch todo_url(@todo), params: { todo: { title: "Bob edited this" } }
    assert_redirected_to todos_url
    assert_equal "Bob edited this", @todo.reload.title
  end

  test "a user in a different household cannot edit the todo" do
    sign_in users(:three) # carol, household :two

    patch todo_url(@todo), params: { todo: { title: "Should not work" } }
    assert_response :not_found
  end

  # ── Weekly planning ──

  test "the board shows the week's time and the new columns" do
    get todos_url
    assert_select "#todo_budget"
    assert_select "h2", text: "To-Do This Week"
    assert_select "h2", text: "Completed"
  end

  test "plan adds a to-do to the week being planned" do
    next_week = Date.current.beginning_of_week + 7
    patch plan_todo_url(@todo), params: { plan: "add", week: next_week.iso8601 }

    @todo.reload
    assert_equal "in_progress", @todo.status
    assert_equal next_week, @todo.planned_week
  end

  test "plan marks a carried-over to-do complete in the week it was planned for" do
    last_week = Date.current.beginning_of_week - 7
    @todo.update!(status: "in_progress", planned_week: last_week, estimated_time_to_complete: 30)

    patch plan_todo_url(@todo), params: { plan: "complete", week: (last_week + 7).iso8601 }

    @todo.reload
    assert_equal "done", @todo.status
    assert_equal last_week, @todo.planned_week
    assert_equal 30, @todo.actual_time_to_complete
  end

  test "plan can put a to-do back in the To-Do column" do
    @todo.update!(status: "in_progress", planned_week: Date.current.beginning_of_week)
    patch plan_todo_url(@todo), params: { plan: "remove", week: Date.current.beginning_of_week.iso8601 }

    assert_equal "todo", @todo.reload.status
    assert_nil @todo.planned_week
  end

  test "reordering part of a column keeps the rest of it where it was" do
    household = households(:one)
    a, b, c = %w[A B C].map do |title|
      household.todos.create!(user: users(:one), title:, priority: :medium, status: "in_progress")
    end

    post reorder_todos_url, params: { status: "in_progress", order: [ c.id, a.id ] }, as: :json

    assert_equal [ c, b, a ], household.todos.where(id: [ a, b, c ]).ordered.to_a
  end

  test "tag names set the to-do's tags from the household's own" do
    mine   = households(:one).todo_tags.create!(name: "Yard")
    theirs = households(:two).todo_tags.create!(name: "Garage")
    @todo.tags << mine

    patch todo_url(@todo), params: { todo: { tag_names: "Garage" } }

    assert_equal [ "Garage" ], @todo.reload.tags.map(&:name)
    assert_not_includes @todo.tags, theirs # household :one got its own
    assert_not_includes @todo.tags, mine   # taken off
  end

  test "the time for to-dos can be changed from the board" do
    patch todo_budget_url, params: { household: { todo_hours_per_week: "7.5" } }, headers: { "HTTP_REFERER" => todos_url }

    assert_redirected_to todos_url
    assert_equal 450, households(:one).reload.todo_minutes_per_week
  end

  test "planning a to-do redraws the plan-week step in place" do
    patch plan_todo_url(@todo), params: { plan: "add", week: Date.current.beginning_of_week.iso8601 }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][target=plan_week_todos][method=morph]"
    assert_select "#planned_todos #plan_todo_#{@todo.id}"
  end

  test "reordering from plan-week sends back the meter and chart" do
    post reorder_todos_url(status: "in_progress", week: Date.current.beginning_of_week.iso8601),
         params: { order: [ @todo.id ] }, as: :json, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "turbo-stream[action=replace][target=gantt_chart]"
  end

  test "changing the time for to-dos swaps the meter and chart in place" do
    patch todo_budget_url, params: { household: { todo_hours_per_week: "7.5" } }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=replace][target=todo_budget]"
    assert_select "turbo-stream[action=replace][target=gantt_chart]"
  end
end
