class TodosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_todo, only: %i[edit update destroy]

  def index
    @todos_by_status = Todo::STATUSES.index_with do |status|
      current_user.todos.by_status(status)
    end
  end

  def new
    @todo = current_user.todos.new(status: params[:status] || "todo", priority: :medium)
  end

  def create
    @todo = current_user.todos.new(todo_params)
    if @todo.save
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
    if @todo.update(todo_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todos_path }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @todo.destroy
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

    head :ok
  end

  # POST /todos/:id/move
  # Params: { status: "in_progress", position: 2 }
  def move
    set_todo
    new_status = params[:status]
    return head :bad_request unless Todo::STATUSES.include?(new_status)

    @todo.move_to_column!(new_status, params[:position])

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
    params.require(:todo).permit(:title, :description, :priority, :status)
  end
end