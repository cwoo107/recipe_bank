class TodosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_todo, only: %i[edit update destroy]

  def index
    @todos_by_status = Todo::STATUSES.index_with do |status|
      scope = current_household.todos.by_status(status)

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
    if @todo.save
      # A brand-new todo created directly into "in_progress" or "done" never had
      # a previous status, so we pass nil (treated as "not in_progress").
      reschedule_from = @todo.apply_status_side_effects!(nil)
      refresh_schedule_and_chart(reschedule_from)
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
      reschedule_from = @todo.status != previous_status ? @todo.apply_status_side_effects!(previous_status) : Date.current
      refresh_schedule_and_chart(reschedule_from)
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
      current_household.todos
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
    reschedule_from = @todo.apply_status_side_effects!(previous_status)
    refresh_schedule_and_chart(reschedule_from)
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

  def todo_params
    params.require(:todo).permit(
      :title, :description, :priority, :status,
      :estimated_hours, :estimated_minutes
    )
  end

  # Recompute the in-progress timeline, then push the refreshed Gantt chart to
  # every open board via Turbo Streams. `reschedule_from` is the cursor date
  # to pack the queue from; pass `false` (as `apply_status_side_effects!` can)
  # to skip repacking entirely — e.g. completing a todo that was already at
  # the front of the queue shouldn't move anyone else's start date.
  def refresh_schedule_and_chart(reschedule_from = Date.current)
    Todo.reschedule_in_progress!(current_household, from: reschedule_from) if reschedule_from
    Todo.broadcast_gantt(current_household)
  end
end