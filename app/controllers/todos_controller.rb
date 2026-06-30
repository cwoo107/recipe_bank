class TodosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_todo, only: %i[edit update destroy]

  def index
    @todos_by_status = Todo::STATUSES.index_with do |status|
      scope = current_user.todos.by_status(status)

      scope = scope.ended_this_week if status == "done"
      scope
    end
  end


  def new
    @todo = current_user.todos.new(status: params[:status] || "todo", priority: :medium)
  end

  def create
    @todo = current_user.todos.new(todo_params)
    if @todo.save
      # A brand-new todo created directly into "in_progress" or "done" never had
      # a previous status, so we pass nil (treated as "not in_progress").
      @todo.apply_status_side_effects!(nil)
      refresh_schedule_and_chart
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
      refresh_schedule_and_chart
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
    was_in_progress = @todo.status == "in_progress"
    @todo.destroy

    # Removing an in-progress todo frees up the timeline, so the rest shift up.
    refresh_schedule_and_chart if was_in_progress

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("todo_#{@todo.id}") }
      format.html { redirect_to todos_path }
    end
  end

  # POST /todos/reorder
  # Params: { status: "todo", order: ["1","4","2"] }
  def reorder
    status = params[:status]
    return head :bad_request unless Todo::STATUSES.include?(status)

    Array(params[:order]).each_with_index do |id, index|
      current_user.todos
                  .where(status: status, id: id)
                  .update_all(position: index + 1)
    end

    # Position is the tie-breaker between equal-priority todos, so a reorder
    # within "in_progress" can change the schedule. Broadcast handles the chart.
    refresh_schedule_and_chart if status == "in_progress"

    head :ok
  end

  # POST /todos/:id/move
  # Params: { status: "in_progress", position: 2 }
  def move
    set_todo
    new_status = params[:status]
    return head :bad_request unless Todo::STATUSES.include?(new_status)

    previous_status = @todo.status
    @todo.move_to_column!(new_status, params[:position])
    @todo.apply_status_side_effects!(previous_status)
    refresh_schedule_and_chart
    @todo.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to todos_path }
    end
  end

  private

  def set_todo
    @todo = current_user.todos.find(params[:id])
  end

  def todo_params
    params.require(:todo).permit(
      :title, :description, :priority, :status,
      :estimated_hours, :estimated_minutes
    )
  end

  # Recompute the in-progress timeline, then push the refreshed Gantt chart to
  # every open board via Turbo Streams.
  def refresh_schedule_and_chart
    Todo.reschedule_in_progress!(current_user)
    Todo.broadcast_gantt(current_user)
  end
end