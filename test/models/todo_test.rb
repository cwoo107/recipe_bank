require "test_helper"

class TodoTest < ActiveSupport::TestCase
  test "position is scoped to household and status, shared across members" do
    household = households(:one)
    alice = users(:one)
    bob = users(:two) # also in household :one

    first = household.todos.create!(user: alice, title: "First", priority: :medium, status: "in_progress")
    second = household.todos.create!(user: bob, title: "Second", priority: :medium, status: "in_progress")

    assert_equal 1, first.reload.position
    assert_equal 2, second.reload.position
  end

  test "gantt_data is scoped to the household, not a single member" do
    household = households(:one)
    household.todos.create!(user: users(:one), title: "Alice's task", priority: :high, status: "in_progress",
                             start_date: Date.current, end_date: Date.current)
    household.todos.create!(user: users(:two), title: "Bob's task", priority: :low, status: "in_progress",
                             start_date: Date.current, end_date: Date.current)

    data = Todo.gantt_data(household)
    assert_equal 2, data[:rows].size
  end

  test "reschedule_in_progress! spans fewer days when the household has more minutes per day" do
    household = households(:one)
    household.update!(minutes_per_day: 120)
    todo = household.todos.create!(user: users(:one), title: "Two hour task", priority: :medium,
                                    status: "in_progress", estimated_time_to_complete: 120)

    Todo.reschedule_in_progress!(household)
    todo.reload

    assert_equal Date.current, todo.start_date.to_date
    assert_equal Date.current, todo.end_date.to_date
  end

  test "reschedule_in_progress! spans more days when the household has fewer minutes per day" do
    household = households(:one)
    household.update!(minutes_per_day: 15)
    todo = household.todos.create!(user: users(:one), title: "Half hour task", priority: :medium,
                                    status: "in_progress", estimated_time_to_complete: 30)

    Todo.reschedule_in_progress!(household)
    todo.reload

    assert_equal Date.current, todo.start_date.to_date
    assert_equal Date.current + 1, todo.end_date.to_date
  end

  test "completing a todo already at the front of the queue leaves everyone else's schedule alone" do
    household = households(:one)
    front = household.todos.create!(user: users(:one), title: "Front", priority: :high, status: "in_progress",
                                     start_date: Date.current, end_date: Date.current)
    behind = household.todos.create!(user: users(:one), title: "Behind", priority: :low, status: "in_progress",
                                      start_date: Date.current + 1, end_date: Date.current + 1)

    front.status = "done"
    reschedule_from = front.apply_status_side_effects!("in_progress")
    Todo.reschedule_in_progress!(household, from: reschedule_from) if reschedule_from

    assert_equal false, reschedule_from
    assert_equal Date.current + 1, behind.reload.start_date.to_date
  end

  test "completing a todo ahead of its scheduled slot shifts the rest of the queue to start after it" do
    household = households(:one)
    jumped = household.todos.create!(user: users(:one), title: "Jumped ahead", priority: :low, status: "in_progress",
                                      start_date: Date.current + 1, end_date: Date.current + 1,
                                      estimated_time_to_complete: household.minutes_per_day)
    skipped = household.todos.create!(user: users(:one), title: "Skipped today", priority: :high,
                                       status: "in_progress", start_date: Date.current, end_date: Date.current,
                                       estimated_time_to_complete: household.minutes_per_day)

    jumped.status = "done"
    reschedule_from = jumped.apply_status_side_effects!("in_progress")
    Todo.reschedule_in_progress!(household, from: reschedule_from) if reschedule_from

    assert_equal Date.current, jumped.start_date.to_date
    assert_equal Date.current, jumped.end_date.to_date
    assert_equal Date.current + 1, skipped.reload.start_date.to_date
  end

  test "completing an in-progress task derives actual time from minutes_per_day, not the estimate" do
    household = households(:one)
    household.update!(minutes_per_day: 60)
    todo = household.todos.create!(user: users(:one), title: "Multi-day task", priority: :medium,
                                    status: "in_progress", estimated_time_to_complete: 45,
                                    start_date: Date.current - 1, end_date: Date.current)

    todo.status = "done"
    todo.apply_status_side_effects!("in_progress")

    # 2 calendar days (inclusive) * 60 minutes_per_day, regardless of the 45-minute estimate.
    assert_equal 120, todo.actual_time_to_complete
  end
end
