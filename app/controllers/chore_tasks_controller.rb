# Adds, renames and removes a chore's tasks from Manage Chores (the Tasks
# column on desktop, the edit modal on mobile). Every response re-renders
# the chore's task lists in place — see chore_tasks/refresh.turbo_stream.erb.
class ChoreTasksController < ApplicationController
  # Limited members can look but not change these (see ApplicationController).
  before_action :require_household_admin!
  before_action :set_chore
  before_action :set_chore_task, only: %i[update destroy]

  def create
    @chore_task = @chore.chore_tasks.new(chore_task_params)
    @chore_task.save
    # After adding one with Enter, keep the "Add a task" field open (and
    # focused) in whichever list it came from, so a run of tasks can be typed
    # in a row. Not after clicking away (keep_open=0) — focus went elsewhere.
    @adding_in = from unless params[:keep_open] == "0"
    refresh
  end

  def update
    @chore_task.update(chore_task_params)
    refresh
  end

  def destroy
    @chore_task.destroy!
    refresh
  end

  private

  def set_chore
    @chore = current_household.chores.find(params[:chore_id])
  end

  def set_chore_task
    @chore_task = @chore.chore_tasks.find(params[:id])
  end

  def chore_task_params
    params.require(:chore_task).permit(:name)
  end

  def from
    params[:from] == "mobile" ? "mobile" : "desktop"
  end

  def refresh
    @chore.chore_tasks.reset
    respond_to do |format|
      format.turbo_stream { render :refresh, status: @chore_task.errors.any? ? :unprocessable_entity : :ok }
      format.html { redirect_to chores_path, status: :see_other }
    end
  end
end
