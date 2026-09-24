require "test_helper"

# The create response only prepends the new card, so the quick-add form stays
# standing — it has to clear itself or the next click re-submits the same task.
class TodoFormResetTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "the new-task form is wired to clear itself once saved" do
    get new_todo_url

    assert_response :success
    assert_select "form[data-controller=?]", "dialog-form"
    assert_select "form[data-dialog-form-clear-on-success-value=?]", "true"
    assert_select "form[data-action=?]", "turbo:submit-end->dialog-form#submitEnd"
  end

  test "a column quick-add form clears itself too" do
    get new_todo_url(status: "in_progress")

    assert_response :success
    assert_select "form[data-dialog-form-clear-on-success-value=?]", "true"
  end

  test "the edit form keeps what was saved instead of blanking" do
    todo = current_household_todos.create!(title: "Existing", status: "todo",
                                           priority: :medium, user: @user)

    get edit_todo_url(todo)

    assert_response :success
    assert_select "form[data-dialog-form-clear-on-success-value=?]", "false"
  end

  test "the form no longer carries the targetless dialog controller" do
    get new_todo_url

    # `data-controller="dialog"` on the form itself bound submit->dialog#close
    # to an instance with no dialog target, so the close threw and the filled
    # form stayed on screen.
    assert_select "form[data-controller=?]", "dialog", count: 0
    assert_select "form[data-action*=?]", "submit->dialog#close", count: 0
  end

  test "creating a task still streams the new card in" do
    assert_difference("Todo.count", 1) do
      post todos_url, params: { todo: { title: "Buy milk", status: "todo", priority: "medium" } },
                      as: :turbo_stream
    end

    assert_response :success
    todo = Todo.order(:id).last
    assert_match "todo_#{todo.id}", response.body
    assert_match "Buy milk", response.body
  end

  private

  def current_household_todos
    @user.household.todos
  end
end
