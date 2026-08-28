require "test_helper"

class WeeklyChoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chore = chores(:one) # belongs to household :one (alice + bob)
    sign_in users(:one) # alice
  end

  test "should get index" do
    get weekly_chores_url
    assert_response :success
  end

  test "index lists due chores that aren't already on this week's list" do
    get weekly_chores_url
    assert_select "button", text: "Add to this week"
  end

  test "create adds a chore to this week's list" do
    assert_difference("WeeklyChore.count") do
      post weekly_chores_url, params: { chore_id: @chore.id, week_start: Date.current.beginning_of_week }
    end

    assert_equal households(:one), WeeklyChore.last.household
  end

  test "create is scoped to the current household's chores" do
    other_chore = chores(:two) # household :two

    assert_no_difference("WeeklyChore.count") do
      post weekly_chores_url, params: { chore_id: other_chore.id, week_start: Date.current.beginning_of_week }
    end

    assert_response :not_found
  end

  test "create can drop a due chore directly onto a day" do
    week_start = Date.current.beginning_of_week

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 2 }

    assert_equal week_start + 2, WeeklyChore.last.scheduled_date
  end

  test "create is idempotent — a second drop of the same due chore moves it instead of erroring" do
    week_start = Date.current.beginning_of_week

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 1 }
    assert_response :redirect

    assert_no_difference("WeeklyChore.count") do
      post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start, scheduled_date: week_start + 3 }
    end
    assert_response :redirect

    assert_equal week_start + 3, WeeklyChore.last.scheduled_date
  end

  test "move schedules a weekly chore onto a day" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: week_start + 3 }

    assert_equal week_start + 3, weekly_chore.reload.scheduled_date
  end

  test "move back to an empty scheduled_date returns the chore to unscheduled" do
    week_start = Date.current.beginning_of_week
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 3)

    post move_weekly_chore_url(weekly_chore), params: { scheduled_date: "" }

    assert_nil weekly_chore.reload.scheduled_date
  end

  test "reorder updates position within a day" do
    week_start = Date.current.beginning_of_week
    other_chore = households(:one).chores.create!(name: "Vacuum", frequency: "weekly")
    first = households(:one).weekly_chores.create!(chore: @chore, week_start: week_start, scheduled_date: week_start + 1)
    second = households(:one).weekly_chores.create!(chore: other_chore, week_start: week_start, scheduled_date: week_start + 1)

    post reorder_weekly_chores_url, params: { scheduled_date: week_start + 1, order: [ second.id, first.id ] }

    assert_equal 1, second.reload.position
    assert_equal 2, first.reload.position
  end

  test "update toggles completion and stamps the chore's last_completed_at" do
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    patch weekly_chore_url(weekly_chore), params: { weekly_chore: { completed: true } }

    assert weekly_chore.reload.completed?
    assert_not_nil @chore.reload.last_completed_at
  end

  test "should destroy weekly chore" do
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    assert_difference("WeeklyChore.count", -1) do
      delete weekly_chore_url(weekly_chore)
    end
  end

  test "destroying a still-due weekly chore puts it back in the due soon list" do
    @chore.update!(last_completed_at: nil) # never completed -> always due
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    delete weekly_chore_url(weekly_chore), as: :turbo_stream

    assert_match(/due_chore_#{@chore.id}/, response.body)
  end

  test "destroying a weekly chore that isn't due yet does not reappear in due soon" do
    @chore.update!(last_completed_at: Date.current) # weekly chore, just completed -> not due again soon
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)

    delete weekly_chore_url(weekly_chore), as: :turbo_stream

    assert_no_match(/due_chore_#{@chore.id}/, response.body)
  end

  test "create with no explicit day fills in the first day that doesn't already have a chore" do
    week_start = Date.current.beginning_of_week
    other_chore = households(:one).chores.create!(name: "Vacuum", frequency: "weekly")
    households(:one).weekly_chores.create!(chore: other_chore, week_start: week_start, scheduled_date: week_start) # Monday taken

    post weekly_chores_url, params: { chore_id: @chore.id, week_start: week_start }

    assert_equal week_start + 1, WeeklyChore.last.scheduled_date # Tuesday, the first open day
  end

  test "a user in a different household cannot modify the weekly chore" do
    weekly_chore = households(:one).weekly_chores.create!(chore: @chore, week_start: Date.current.beginning_of_week)
    sign_in users(:three) # carol, household :two

    patch weekly_chore_url(weekly_chore), params: { weekly_chore: { completed: true } }
    assert_response :not_found
  end
end
