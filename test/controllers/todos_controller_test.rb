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

  test "another member of the same household can see and edit the todo" do
    sign_in users(:two) # bob, also in household :one

    patch todo_url(@todo), params: { todo: { title: "Bob edited this" } }
    assert_redirected_to todos_url
    assert_equal "Bob edited this", @todo.reload.title
  end

  test "a user in a different household cannot edit the todo" do
    sign_in users(:three) # carol, household :two

    patch todo_url(@todo), params: { todo: { title: "Should not work" } }
    assert_response :not_found
  end
end
