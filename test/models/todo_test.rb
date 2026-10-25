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

  test "the week's plan is scoped to the household, not a single member" do
    household = households(:one)
    household.todos.create!(user: users(:one), title: "Alice's task", priority: :high, status: "in_progress",
                            planned_week: this_week(household), estimated_time_to_complete: 60)
    household.todos.create!(user: users(:two), title: "Bob's task", priority: :low, status: "in_progress",
                            planned_week: this_week(household), estimated_time_to_complete: 30)

    budget = TodoBudget.new(household)
    assert_equal 2, budget.gantt_data[:rows].size
    assert_equal 90, budget.planned_minutes
  end

  test "each to-do takes its own block of the week's hours, in the column's order" do
    household = households(:one)
    second = household.todos.create!(user: users(:one), title: "Second", priority: :urgent, status: "in_progress",
                                     planned_week: this_week(household), estimated_time_to_complete: 90)
    first = household.todos.create!(user: users(:one), title: "First", priority: :low, status: "in_progress",
                                    planned_week: this_week(household), estimated_time_to_complete: 60)
    first.insert_at(1)

    rows = TodoBudget.new(household).gantt_data[:rows]
    assert_equal [ "First", "Second" ], rows.map { |r| r[:title] }
    assert_equal [ 0.0, 1.0 ], [ rows[0][:start], rows[0][:end] ]
    assert_equal [ 1.0, 2.5 ], [ rows[1][:start], rows[1][:end] ]
    assert_equal second.id, rows[1][:id]
  end

  test "the budget is the weekly time, or the daily time times seven" do
    household = households(:one)
    household.update!(todo_time_period: "week", todo_hours_per_week: 6)
    assert_equal 360, household.todo_minutes_budget

    household.update!(todo_time_period: "day", minutes_per_day: 30)
    assert_equal 210, household.todo_minutes_budget
  end

  test "the meter goes green, yellow, then red as the week fills up" do
    household = households(:one)
    household.update!(todo_time_period: "week", todo_hours_per_week: 6)
    todo = household.todos.create!(user: users(:one), title: "Paint", priority: :medium, status: "in_progress",
                                   planned_week: this_week(household), estimated_time_to_complete: 60)

    assert_equal :plenty, TodoBudget.new(household).state

    todo.update!(estimated_time_to_complete: 300)
    assert_equal :close, TodoBudget.new(household).state

    todo.update!(estimated_time_to_complete: 420)
    budget = TodoBudget.new(household)
    assert_equal :over, budget.state
    assert_equal "You've set aside 6 hours for to-dos, but you have planned 7 hours.", budget.message
  end

  test "moving a to-do into This Week plans it for the current week; back to To-Do unplans it" do
    household = households(:one)
    todo = household.todos.create!(user: users(:one), title: "Rake leaves", priority: :medium, status: "todo")

    todo.move_to_column!("in_progress")
    todo.apply_status_side_effects!("todo")
    assert_equal this_week(household), todo.reload.planned_week

    todo.move_to_column!("todo")
    todo.apply_status_side_effects!("in_progress")
    assert_nil todo.reload.planned_week
  end

  test "completing a to-do takes its estimate as the time it took, and counts it in this week" do
    household = households(:one)
    todo = household.todos.create!(user: users(:one), title: "Fix gate", priority: :medium, status: "in_progress",
                                   planned_week: this_week(household) - 7, estimated_time_to_complete: 45)

    todo.move_to_column!("done")
    todo.apply_status_side_effects!("in_progress")

    assert todo.completed?
    assert_equal 45, todo.actual_time_to_complete
    assert_equal this_week(household), todo.planned_week
    assert_includes TodoBudget.new(household).todos, todo
  end

  test "to-dos left from an earlier week carry into the current week until they're dealt with" do
    household = households(:one)
    old = household.todos.create!(user: users(:one), title: "Left over", priority: :medium, status: "in_progress",
                                  planned_week: this_week(household) - 7)
    later = household.todos.create!(user: users(:one), title: "Next week's", priority: :medium, status: "in_progress",
                                    planned_week: this_week(household) + 7)

    assert_includes Todo.open_for_week(household, this_week(household)), old
    assert_not_includes Todo.open_for_week(household, this_week(household)), later
    assert_equal [ old ], Todo.carried_over(household, this_week(household)).to_a
    # Planning next week, this week's open ones are the ones to settle.
    assert_not_includes Todo.open_for_week(household, this_week(household) + 7), old
    assert_includes Todo.carried_over(household, this_week(household) + 7), old
  end

  test "tag names are created for the household as needed and set on the to-do" do
    household = households(:one)
    existing = household.todo_tags.create!(name: "Yard")
    todo = household.todos.create!(user: users(:one), title: "Mow", priority: :medium, status: "todo",
                                   tag_names: "yard, Paperwork ,")

    assert_equal [ "Paperwork", "Yard" ], todo.reload.tags.map(&:name)
    assert_includes todo.tags, existing
    assert_equal 2, household.todo_tags.count
  end

  private

  def this_week(household) = Todo.current_week_start(household)
end
