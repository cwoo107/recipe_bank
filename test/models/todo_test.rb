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
end
