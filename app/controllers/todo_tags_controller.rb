# The household's to-do tags, managed from a dialog on the board (new ones
# can also be typed straight into a to-do's form). Everything renders inside
# the dialog's "todo_tags" frame.
class TodoTagsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_household_admin!, except: :index
  before_action :set_todo_tag, only: %i[update destroy]

  def index
    @todo_tags = current_household.todo_tags.ordered
    @todo_tag  = current_household.todo_tags.new
  end

  def create
    @todo_tag = current_household.todo_tags.new(todo_tag_params)
    if @todo_tag.save
      redirect_to todo_tags_path, status: :see_other
    else
      @todo_tags = current_household.todo_tags.ordered
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @todo_tag.update(todo_tag_params)
      redirect_to todo_tags_path, status: :see_other
    else
      @todo_tags = current_household.todo_tags.ordered
      @todo_tag_with_errors = @todo_tag
      @todo_tag = current_household.todo_tags.new
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @todo_tag.destroy
    redirect_to todo_tags_path, status: :see_other
  end

  private

  def set_todo_tag
    @todo_tag = current_household.todo_tags.find(params[:id])
  end

  def todo_tag_params
    params.expect(todo_tag: [ :name, :color ])
  end
end
