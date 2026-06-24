class TagsController < ApplicationController
  before_action :set_tag, only: %i[show edit update destroy]

  def index
    @tags = current_user.tags.includes(:recipes)
  end

  def show
  end

  def new
    @tag = current_user.tags.build
  end

  def edit
  end

  def create
    @tag = current_user.tags.build(tag_params)

    if @tag.save
      redirect_to tags_path, notice: "Tag was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @tag.update(tag_params)
      redirect_to tags_path, notice: "Tag was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tag.destroy!
    redirect_to tags_path, notice: "Tag was successfully deleted.", status: :see_other
  end

  private

  def set_tag
    # Scoped to current_user — users can't access each other's tags
    @tag = current_user.tags.find(params.expect(:id))
  end

  def tag_params
    params.expect(tag: [:tag, :color])
  end
end