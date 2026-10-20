require "test_helper"

class ChoreTasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chore = chores(:one) # household :one
    sign_in users(:one)   # alice, admin
  end

  test "create adds a task and keeps the add field open in the list it came from" do
    assert_difference("@chore.chore_tasks.count") do
      post chore_chore_tasks_url(@chore), params: { from: "desktop", chore_task: { name: "Rinse bins" } }, as: :turbo_stream
    end

    assert_equal "Rinse bins", @chore.chore_tasks.last.name
    assert_match(/chore_tasks_desktop_#{@chore.id}/, response.body)
    assert_match(/data-task-adder-open-value="true"/, response.body)
  end

  test "create after clicking away doesn't reopen the add field" do
    post chore_chore_tasks_url(@chore), params: { from: "desktop", keep_open: "0", chore_task: { name: "Rinse bins" } }, as: :turbo_stream
    assert_no_match(/data-task-adder-open-value="true"/, response.body)
  end

  test "tasks keep the order they were added in" do
    %w[Toilet Floors Sink].each do |name|
      post chore_chore_tasks_url(@chore), params: { chore_task: { name: name } }, as: :turbo_stream
    end
    assert_equal %w[Toilet Floors Sink], @chore.chore_tasks.reload.map(&:name)
  end

  test "a blank task isn't saved" do
    assert_no_difference("ChoreTask.count") do
      post chore_chore_tasks_url(@chore), params: { chore_task: { name: "  " } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "update renames and destroy removes a task" do
    task = @chore.chore_tasks.create!(name: "Toilet")

    patch chore_chore_task_url(@chore, task), params: { chore_task: { name: "Scrub toilet" } }, as: :turbo_stream
    assert_equal "Scrub toilet", task.reload.name

    delete chore_chore_task_url(@chore, task), as: :turbo_stream
    assert_nil ChoreTask.find_by(id: task.id)
  end

  test "can't touch another household's chore tasks" do
    other = chores(:two).chore_tasks.create!(name: "Oven")

    post chore_chore_tasks_url(chores(:two)), params: { chore_task: { name: "Nope" } }
    assert_response :not_found

    sign_in users(:one) # a 404 response doesn't carry the test sign-in forward
    delete chore_chore_task_url(chores(:two), other)
    assert_response :not_found
  end

  test "limited members can't change tasks" do
    sign_in users(:two) # bob, limited
    assert_no_difference("ChoreTask.count") do
      post chore_chore_tasks_url(@chore), params: { chore_task: { name: "Rinse bins" } }
    end
  end

  test "the Table View lists tasks with an add-a-task link" do
    @chore.chore_tasks.create!(name: "Rinse bins")
    get weekly_chores_url(view: "table")

    assert_select "#chore_tasks_desktop_#{@chore.id}" do
      assert_select "[data-inline-cell-target=text]", text: "Rinse bins"
      assert_select "button", text: /Add a task/
    end
  end

  test "the schedule card lists the chore's tasks" do
    week_start = Date.current.beginning_of_week
    @chore.chore_tasks.create!(name: "Rinse bins")
    @chore.chore_tasks.create!(name: "Wheel to curb")
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    get weekly_chores_url

    # Scoped to the desktop grid — the card renders again in the mobile layout.
    desktop_cell = "#weekly_chores_cell_desktop_#{(week_start + 1).iso8601}_#{chore_categories(:chores_one).id}"
    assert_select "#{desktop_cell} #weekly_chore_#{weekly_chore.id} .chore-tasks-board-#{@chore.id}" do
      # Clicking a task removes it, after the app's confirm dialog.
      assert_select "form[action=?] button[data-turbo-confirm=?]",
                    chore_chore_task_path(@chore, @chore.chore_tasks.first, from: "board"),
                    %(Remove the task "Rinse bins" from #{@chore.name}?), text: /Rinse bins/
      assert_select "button[data-turbo-confirm]", 2
      assert_select "button", text: "Remove", count: 0
      assert_select "[data-controller=inline-cell]", 0
      assert_select "button", text: /Add a task/
    end
  end

  test "a limited member sees a card's tasks without the controls" do
    sign_in users(:two) # bob, limited
    week_start = Date.current.beginning_of_week
    @chore.chore_tasks.create!(name: "Rinse bins")
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)

    get weekly_chores_url

    assert_select "#weekly_chore_#{weekly_chore.id} ul[aria-label=Tasks] li", text: /Rinse bins/
    assert_select "#weekly_chore_#{weekly_chore.id} button", text: /Add a task/, count: 0
  end

  test "a task added from a board card refreshes every copy of the card" do
    post chore_chore_tasks_url(@chore), params: { from: "board", chore_task: { name: "Rinse bins" } }, as: :turbo_stream

    assert_response :success
    assert_match %(targets=".chore-tasks-board-#{@chore.id}"), response.body
    assert_match "Rinse bins", response.body
  end
end
