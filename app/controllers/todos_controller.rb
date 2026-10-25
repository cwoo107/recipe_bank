class TodosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_todo, only: %i[edit update destroy]
  # Limited members: a to-do they created is theirs to edit or delete; one an
  # admin assigned to them can only change status (move/drag to Done); anyone
  # else's is read-only. Reordering a whole column is admin-only.
  before_action :require_todo_editable!, only: %i[edit update destroy]
  before_action :require_household_admin!, only: %i[reorder plan]

  def index
    @budget = TodoBudget.new(current_household)
    @todos_by_status = Todo::STATUSES.index_with do |status|
      scope = current_household.todos.by_status(status).includes(:assignee, :tags)

      scope = scope.ended_this_week if status == "done"
      scope
    end
  end


  def new
    @todo = current_household.todos.new(status: params[:status] || "todo", priority: :medium, user: current_user)
  end

  def create
    @todo = current_household.todos.new(todo_params)
    @todo.user = current_user
    @todo.assignee = current_member unless household_admin? # limited members' to-dos are their own
    if @todo.save
      # A brand-new todo never had a previous status, so a "To-Do This Week"
      # one is planned for this week and a "Completed" one stamped done now.
      @todo.apply_status_side_effects!(nil)
      Todo.broadcast_gantt(current_household)
      @todo.reload

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todos_path }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    previous_status = @todo.status

    if @todo.update(todo_params)
      @todo.apply_status_side_effects!(previous_status) if @todo.status != previous_status
      # Even without a move, a new estimate changes the week's time.
      Todo.broadcast_gantt(current_household)
      @todo.reload

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todos_path }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    was_planned = @todo.status != "todo"
    @todo.destroy

    # Removing a planned to-do frees up the week's time.
    Todo.broadcast_gantt(current_household) if was_planned

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("todo_#{@todo.id}") }
      format.html { redirect_to todos_path }
    end
  end

  # POST /todos/reorder
  # Params: { status: "todo", order: ["1","4","2"] }
  #
  # The order can be part of a column — "Plan your week" sorts just one
  # week's to-dos — so the listed to-dos swap among the positions they
  # already hold, leaving everything else in the column where it was.
  def reorder
    status = params[:status]
    return head :bad_request unless Todo::STATUSES.include?(status)

    ids   = Array(params[:order]).map(&:to_i)
    todos = current_household.todos.where(status: status, id: ids).index_by(&:id)
    slots = todos.values.map(&:position).sort
    ids.select { |id| todos.key?(id) }.uniq.each_with_index do |id, index|
      todos[id].update_column(:position, slots[index])
    end

    # The This Week column's order is the Gantt's order.
    Todo.broadcast_gantt(current_household) if status == "in_progress"

    head :ok
  end

  # PATCH /todos/:id/plan
  # Params: { week: "2026-10-26", plan: "add" | "complete" | "remove" }
  #
  # "Plan your week": add a to-do to the week being planned (or carry one
  # over from an earlier week), mark one complete, or take it back off to
  # the To-Do column.
  def plan
    set_todo
    week = Date.iso8601(params[:week].to_s).beginning_of_week(current_household.week_start_symbol)
    previous_status = @todo.status

    case params[:plan]
    when "add"
      @todo.move_to_column!("in_progress") unless previous_status == "in_progress"
      @todo.planned_week = week
      @todo.apply_status_side_effects!(previous_status, week: week)
    when "complete"
      @todo.move_to_column!("done")
      # Done during the week it was planned for, as far as anyone knows.
      @todo.apply_status_side_effects!(previous_status, week: @todo.planned_week || Todo.current_week_start(current_household))
    when "remove"
      @todo.move_to_column!("todo")
      @todo.apply_status_side_effects!(previous_status)
    else
      return head :bad_request
    end

    Todo.broadcast_gantt(current_household)
    redirect_back_or_to plan_week_step_path(section: "todos", week: week), status: :see_other
  rescue Date::Error
    head :bad_request
  end

  # POST /todos/:id/move
  # Params: { status: "in_progress", position: 2 }
  def move
    set_todo
    return deny_access("You can only move your own to-dos.") unless helpers.todo_movable?(@todo)
    new_status = params[:status]
    return head :bad_request unless Todo::STATUSES.include?(new_status)

    previous_status = @todo.status
    @todo.move_to_column!(new_status, params[:position])
    @todo.apply_status_side_effects!(previous_status)
    Todo.broadcast_gantt(current_household)
    @todo.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to todos_path }
    end
  end

  private

  def set_todo
    @todo = current_household.todos.find(params[:id])
  end

  def require_todo_editable!
    deny_access("You can only edit to-dos you created.") unless helpers.todo_editable?(@todo)
  end

  def todo_params
    permitted = [ :title, :description, :priority, :status, :estimated_hours, :estimated_minutes, :tag_names ]
    permitted << :assignee_id if household_admin? # limited members can't hand to-dos to others
    scoped_assignee_params(params.require(:todo).permit(*permitted))
  end
end